import SwiftUI
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
    static let shared = try? GhosttyTerminalHost(loadDefaultTheme: false)

    /// Built once: user's config + Runway's neutral theme last. Applied app-wide
    /// here; each surface also gets it via `session.updateConfig` after it attaches.
    static let themedConfig: ghostty_config_t? = {
        guard let cfg = ghostty_config_new() else { return nil }
        ghostty_config_load_default_files(cfg)
        RunwayTerminal.themeFilePath.withCString { ghostty_config_load_file(cfg, $0) }
        ghostty_config_finalize(cfg)
        if let app = shared?.app { ghostty_app_update_config(app, cfg) }
        return cfg
    }()
}

/// The swappable terminal seam. Everything in Runway embeds `TerminalSurfaceView`;
/// switching the terminal engine means rewriting only this file. Today it is
/// backed by libghostty's GPU renderer via GhosttyKit.
struct TerminalSurfaceView: View {
    let boxID: UUID
    @State private var session: GhosttyTerminalSession

    init(boxID: UUID, config: TerminalConfig) {
        self.boxID = boxID
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
            .dropDestination(for: URL.self) { urls, _ in
                let text = urls.map { runwayShellEscape($0.path) }.joined(separator: " ")
                guard !text.isEmpty else { return false }
                session.insertText(text + " ")
                Workspace.shared.focusedID = boxID
                return true
            }
    }

    /// Register this box's terminal view so clicks on it resolve to the box.
    private func registerForFocus() {
        if let view = session.view {
            TerminalRegistry.shared.register(view, id: boxID)
        } else {
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 200_000_000)
                if let view = session.view { TerminalRegistry.shared.register(view, id: boxID) }
            }
        }
    }
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
    Task { @MainActor in
        try? await Task.sleep(nanoseconds: 250_000_000)
        session.updateConfig(cfg)
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
