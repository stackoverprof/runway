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

    /// User's config + Runway's neutral theme last. Applied app-wide here; each
    /// surface also gets it via `session.updateConfig` after it attaches.
    /// Rebuilt when the terminal font changes.
    private(set) static var themedConfig: ghostty_config_t? = buildConfig()

    private static func buildConfig() -> ghostty_config_t? {
        guard let cfg = ghostty_config_new() else { return nil }
        ghostty_config_load_default_files(cfg)
        RunwayTerminal.themeFilePath.withCString { ghostty_config_load_file(cfg, $0) }
        ghostty_config_finalize(cfg)
        return cfg
    }

    /// Rewrite the theme file from the current settings and push it to every
    /// live terminal, so a font change lands without restarting the app or
    /// disturbing a single running session.
    static func reloadTheme() {
        RunwayTerminal.installTheme()
        guard let next = buildConfig() else { return }
        let previous = themedConfig
        themedConfig = next
        if let host = shared {
            ghostty_app_update_config(host.app, next)
        }
        for session in RunwayTerminalSessions.live() {
            session.updateConfig(next)
            forceTerminalLayoutUpdate(for: session)
        }
        // Freed only after every surface has taken the new one, the same order
        // GhosttyKit uses for its own config reload.
        if let previous { ghostty_config_free(previous) }
    }
}

/// Live terminal sessions, so a config change can reach all of them. GhosttyKit
/// keeps its own registry but does not publish it.
@MainActor
enum RunwayTerminalSessions {
    private struct WeakSession {
        weak var value: GhosttyTerminalSession?
    }

    private static var sessions: [WeakSession] = []

    static func register(_ session: GhosttyTerminalSession) {
        sessions.removeAll { $0.value == nil || $0.value === session }
        sessions.append(WeakSession(value: session))
    }

    static func live() -> [GhosttyTerminalSession] {
        sessions.removeAll { $0.value == nil }
        return sessions.compactMap(\.value)
    }
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
                        workspace.setFocus(boxID)
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
                            // A surface mounting is not a request to type in it:
                            // if the quick terminal already holds the keyboard,
                            // leave it there and only claim the visual focus.
                            if !didApplyInitialFocus, workspace.focusedID == boxID,
                               !workspace.isQuickTerminalFocused {
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
    // Every session passes through here, so this is where they become reachable
    // for a later font change.
    RunwayTerminalSessions.register(session)
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

/// Naming for images Runway has to materialize itself (a drag that carried only
/// pixels, never a file on disk).
enum DroppedImageFile {
    /// Prefer the name the drag source suggested, so the path typed into the
    /// terminal still reads like the file the user dragged.
    static func name(
        suggested: String?,
        typeIdentifier: String?,
        timestamp: Int
    ) -> String {
        let fallbackExtension = typeIdentifier
            .flatMap(UTType.init)?
            .preferredFilenameExtension ?? "png"
        guard let suggested, !suggested.isEmpty else {
            return "dropped-image-\(timestamp).\(fallbackExtension)"
        }
        let sanitized = suggested
            .components(separatedBy: CharacterSet(charactersIn: "/:\n\r\t"))
            .joined(separator: "-")
            .trimmingCharacters(in: .whitespaces)
        guard !sanitized.isEmpty else {
            return "dropped-image-\(timestamp).\(fallbackExtension)"
        }
        if (sanitized as NSString).pathExtension.isEmpty {
            return "\(sanitized).\(fallbackExtension)"
        }
        return sanitized
    }
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
                    typeDroppedPath(url.path, session: session, onComplete: onComplete)
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

private func typeDroppedPath(
    _ path: String,
    session: GhosttyTerminalSession,
    onComplete: @Sendable @escaping () -> Void
) {
    DispatchQueue.main.async {
        session.insertText(runwayShellEscape(path) + " ")
        onComplete()
    }
}

/// Resolve a dropped image to a path the agent can read.
///
/// The file the user dragged almost always exists on disk already, so ask for it
/// in place first and type that path. Only a drag that carries pixels with no
/// backing file (a screenshot still floating in its preview, an image dragged out
/// of a web page) gets written out, and it goes to Runway's own drops folder.
/// Writing those into ~/Downloads is what used to leave a second copy of every
/// screenshot dropped on a terminal.
private func loadAsImage(
    _ provider: NSItemProvider,
    session: GhosttyTerminalSession,
    onComplete: @Sendable @escaping () -> Void
) {
    let imageType = provider.registeredTypeIdentifiers.first {
        UTType($0)?.conforms(to: .image) == true
    } ?? UTType.image.identifier
    guard provider.hasItemConformingToTypeIdentifier(imageType) else { return }
    nonisolated(unsafe) let safeProvider = provider
    let suggestedName = provider.suggestedName

    _ = provider.loadInPlaceFileRepresentation(forTypeIdentifier: imageType) { url, isInPlace, _ in
        // The URL is only valid for the duration of this callback, so decide and
        // copy here rather than hopping to the main queue with it.
        if let url, FileManager.default.fileExists(atPath: url.path) {
            if isInPlace {
                typeDroppedPath(url.path, session: session, onComplete: onComplete)
                return
            }
            let destination = AgentControl.dropsDir.appendingPathComponent(
                DroppedImageFile.name(
                    suggested: suggestedName ?? url.lastPathComponent,
                    typeIdentifier: imageType,
                    timestamp: Int(Date().timeIntervalSince1970)
                )
            )
            if let adopted = adoptDroppedFile(at: url, to: destination) {
                typeDroppedPath(adopted.path, session: session, onComplete: onComplete)
                return
            }
        }
        writeDroppedImageData(
            safeProvider,
            typeIdentifier: imageType,
            suggestedName: suggestedName,
            session: session,
            onComplete: onComplete
        )
    }
}

private func writeDroppedImageData(
    _ provider: NSItemProvider,
    typeIdentifier: String,
    suggestedName: String?,
    session: GhosttyTerminalSession,
    onComplete: @Sendable @escaping () -> Void
) {
    provider.loadDataRepresentation(forTypeIdentifier: typeIdentifier) { data, _ in
        guard let data else { return }
        let destination = AgentControl.dropsDir.appendingPathComponent(
            DroppedImageFile.name(
                suggested: suggestedName,
                typeIdentifier: typeIdentifier,
                timestamp: Int(Date().timeIntervalSince1970)
            )
        )
        let target = uniqueDropDestination(destination)
        do {
            try data.write(to: target)
            AgentControl.pruneDrops()
            typeDroppedPath(target.path, session: session, onComplete: onComplete)
        } catch {
            NSLog("Runway: failed to write dropped image: \(error.localizedDescription)")
        }
    }
}

private func adoptDroppedFile(at source: URL, to destination: URL) -> URL? {
    let target = uniqueDropDestination(destination)
    do {
        try FileManager.default.copyItem(at: source, to: target)
        AgentControl.pruneDrops()
        return target
    } catch {
        NSLog("Runway: failed to adopt dropped file: \(error.localizedDescription)")
        return nil
    }
}

/// Never overwrite an earlier drop that is still on screen in some terminal.
private func uniqueDropDestination(_ url: URL) -> URL {
    guard FileManager.default.fileExists(atPath: url.path) else { return url }
    let base = url.deletingPathExtension().lastPathComponent
    let ext = url.pathExtension
    for suffix in 2...99 {
        let candidate = url.deletingLastPathComponent()
            .appendingPathComponent(ext.isEmpty ? "\(base)-\(suffix)" : "\(base)-\(suffix).\(ext)")
        if !FileManager.default.fileExists(atPath: candidate.path) { return candidate }
    }
    return url
}
