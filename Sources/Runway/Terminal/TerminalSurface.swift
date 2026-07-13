import SwiftUI
import AppKit
import UniformTypeIdentifiers
import GhosttyKit

/// Engine-agnostic description of what a terminal pane should run. Keeping this
/// separate from the engine means call sites never depend on GhosttyKit.
struct TerminalConfig: Equatable {
    /// Command to launch. `nil` = the user's default login shell.
    var command: String? = nil
    /// Working directory. `nil` = default (home).
    var workingDirectory: String? = nil
    /// Extra environment variables.
    var environment: [String: String] = [:]
}

/// Runway's libghostty host + the themed config used to override colors.
///
/// libghostty loads the user's real Ghostty config and exposes no color API, so
/// we build our own config (their config + our neutral theme loaded LAST, so our
/// colors win) and apply it to the app and to each surface. The `ghostty_*` C
/// symbols come from GhosttyKit's `@_exported import CGhosttyKitBinary`.
@MainActor
enum RunwayTerminalHost {
    static let shared: GhosttyTerminalHost? = {
        let host = try? GhosttyTerminalHost(loadDefaultTheme: false)
        if let host, let cfg = themedConfig {
            ghostty_app_update_config(host.app, cfg)
        }
        return host
    }()

    /// Built once: user's config + Runway's neutral theme last. Applied app-wide
    /// here; each surface also gets it via `session.updateConfig` after it attaches.
    static let themedConfig: ghostty_config_t? = {
        guard let cfg = ghostty_config_new() else { return nil }
        ghostty_config_load_default_files(cfg)
        RunwayTerminal.themeFilePath.withCString { ghostty_config_load_file(cfg, $0) }
        ghostty_config_finalize(cfg)
        return cfg
    }()
}

import UniformTypeIdentifiers

/// The swappable terminal seam. Everything in Runway embeds `TerminalSurfaceView`;
/// switching the terminal engine means rewriting only this file. Today it is
/// backed by libghostty's GPU renderer via GhosttyKit.
struct TerminalSurfaceView: View {
    let boxID: UUID
    let workspace: Workspace
    @State private var session: GhosttyTerminalSession

    init(boxID: UUID, workspace: Workspace, config: TerminalConfig) {
        self.boxID = boxID
        self.workspace = workspace
        let launch = GhosttyTerminalLaunchConfiguration(
            command: config.command,
            workingDirectory: config.workingDirectory,
            environment: config.environment
        )
        if let host = RunwayTerminalHost.shared {
            _session = State(initialValue: host.makeSession(configuration: launch))
        } else {
            _session = State(initialValue: GhosttyTerminalSession(configuration: launch))
        }
    }

    var body: some View {
        GhosttyTerminalRepresentable(session: session, configuration: .default)
            .onAppear { applyRunwayTheme(to: session); registerForFocus() }
            // GhosttyKit's embedded view doesn't accept file drops; replicate
            // Ghostty's behavior by typing the dropped file's path (shell-escaped)
            // into the terminal — Claude Code then picks it up as an image.
            .onDrop(of: [.fileURL, .image], isTargeted: nil) { providers in
                handleDropProviders(providers, session: session) {
                    Task { @MainActor in
                        workspace.focusedID = boxID
                    }
                }
                return true
            }
            .onReceive(NotificationCenter.default.publisher(for: NSWindow.didMoveNotification)) { _ in
                forceTerminalLayoutUpdate(for: session)
            }
            .onReceive(NotificationCenter.default.publisher(for: NSWindow.didChangeScreenNotification)) { _ in
                forceTerminalLayoutUpdate(for: session)
            }
            .onReceive(NotificationCenter.default.publisher(for: NSWindow.didChangeBackingPropertiesNotification)) { _ in
                forceTerminalLayoutUpdate(for: session)
            }
    }

    /// Register this box's terminal view so clicks on it resolve to the box.
    private func registerForFocus() {
        Task { @MainActor in
            for _ in 0..<100 {
                if let view = session.view {
                    TerminalRegistry.shared.register(view, id: boxID)
                    var didApplyInitialFocus = false
                    for delay in [0.05, 0.15, 0.35, 0.75, 1.5, 3.0] {
                        try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                        if view.window != nil {
                            if !didApplyInitialFocus, workspace.focusedID == boxID {
                                view.window?.makeFirstResponder(view)
                                didApplyInitialFocus = true
                            }
                            forceTerminalLayoutUpdate(for: session)
                        }
                    }
                    break
                }
                try? await Task.sleep(nanoseconds: 50_000_000)
            }
        }
    }
}

/// Force libghostty to update its display ID, backing scale factor, and physical surface size.
@MainActor func forceTerminalLayoutUpdate(for session: GhosttyTerminalSession) {
    guard let view = session.view else { return }
    let scale = view.window?.backingScaleFactor ?? 1.0
    view.layer?.contentsScale = scale
    view.viewDidChangeBackingProperties()
    session.updateContentScale()
    session.resize(to: view.bounds.size)
    view.needsLayout = true
    view.needsDisplay = true
}

/// Make a fresh libghostty session backed by Runway's host (falls back to a
/// default session if the host failed to init).
@MainActor func makeRunwaySession(_ config: TerminalConfig = TerminalConfig()) -> GhosttyTerminalSession {
    let launch = GhosttyTerminalLaunchConfiguration(
        command: config.command,
        workingDirectory: config.workingDirectory,
        environment: config.environment
    )
    if let host = RunwayTerminalHost.shared { return host.makeSession(configuration: launch) }
    return GhosttyTerminalSession(configuration: launch)
}

/// Push Runway's themed config onto a session's surface. The surface may not
/// exist on the first call, so retry once shortly after.
@MainActor func applyRunwayTheme(to session: GhosttyTerminalSession) {
    guard let cfg = RunwayTerminalHost.themedConfig else { return }
    session.updateConfig(cfg)
    forceTerminalLayoutUpdate(for: session)
    Task { @MainActor in
        try? await Task.sleep(nanoseconds: 250_000_000)
        session.updateConfig(cfg)
        forceTerminalLayoutUpdate(for: session)
    }
}

/// Backslash-escape shell-special characters (spaces, etc.) like a terminal does
/// on file drop, so paths with spaces (e.g. screenshots) work.
func runwayShellEscape(_ path: String) -> String {
    let special = Set(" \t\"'`\\$&|;<>()[]{}*?!#~")
    var out = ""
    for ch in path {
        if special.contains(ch) { out.append("\\") }
        out.append(ch)
    }
    return out
}

/// Unified, robust drag-and-drop provider handler for file URLs, images, and screenshots
@MainActor func handleDropProviders(
    _ providers: [NSItemProvider],
    session: GhosttyTerminalSession,
    onComplete: @Sendable @escaping () -> Void = {}
) {
    for provider in providers {
        nonisolated(unsafe) let safeProvider = provider
        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                if let url = url, FileManager.default.fileExists(atPath: url.path) {
                    DispatchQueue.main.async {
                        let text = runwayShellEscape(url.path)
                        session.insertText(text + " ")
                        onComplete()
                    }
                } else {
                    // Fall back to image loading if URL was not locally on disk (like a floating screenshot promise)
                    loadAsImage(safeProvider, session: session, onComplete: onComplete)
                }
            }
        } else {
            loadAsImage(safeProvider, session: session, onComplete: onComplete)
        }
    }
}

private func loadAsImage(
    _ provider: NSItemProvider,
    session: GhosttyTerminalSession,
    onComplete: @Sendable @escaping () -> Void
) {
    if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
        provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
            guard let data = data else { return }
            let fm = FileManager.default
            let downloads = fm.urls(for: .downloadsDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSTemporaryDirectory())
            let timestamp = Int(Date().timeIntervalSince1970)
            let fileURL = downloads.appendingPathComponent("Screenshot-\(timestamp).png")
            do {
                try data.write(to: fileURL)
                DispatchQueue.main.async {
                    let text = runwayShellEscape(fileURL.path)
                    session.insertText(text + " ")
                    onComplete()
                }
            } catch {
                print("Failed to write dropped image: \(error)")
            }
        }
    }
}
