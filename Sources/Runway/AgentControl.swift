import SwiftUI
import Foundation

/// Lifecycle state of an agent, shown as the colored header dot.
enum AgentState: String {
    case idle
    case running
    case needsAction

    /// Lenient parse of the `state` value written to the control file.
    init(control value: String) {
        switch value.lowercased().replacingOccurrences(of: "_", with: "-") {
        case "running", "busy", "working": self = .running
        case "needs-action", "needsaction", "attention", "waiting", "blocked", "input": self = .needsAction
        default: self = .idle
        }
    }

    var color: Color {
        switch self {
        case .idle: return Color(red: 0.42, green: 0.45, blue: 0.50)        // grey
        case .running: return Color(red: 0.247, green: 0.725, blue: 0.314)  // green
        case .needsAction: return Color(red: 0.91, green: 0.62, blue: 0.20) // amber
        }
    }

    var glows: Bool { self != .idle }
}

/// The agent control channel + automatic Claude Code state reporting.
///
/// - Any agent/script in a box can set its name/description/state by writing JSON
///   to `$RUNWAY_CONTROL`:  echo '{"state":"running"}' > "$RUNWAY_CONTROL"
/// - For Claude Code specifically, state updates automatically with **zero user
///   setup**: each box's zsh is pointed at a Runway `ZDOTDIR` that sources the
///   user's real config and then defines a `claude` function adding
///   `--settings <runway-hooks>`. The hooks report state to `$RUNWAY_CONTROL`.
///   Nothing in the user's `~/.claude` or `~/.zshrc` is modified.
enum AgentControl {
    static let supportDir: URL = {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let dir = base.appendingPathComponent("Runway", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    static var controlDir: URL { supportDir.appendingPathComponent("control", isDirectory: true) }
    static var zdotdir: URL { supportDir.appendingPathComponent("zsh", isDirectory: true) }
    static var hooksFile: URL { supportDir.appendingPathComponent("claude-hooks.json") }

    static func file(for id: UUID) -> URL {
        controlDir.appendingPathComponent("\(id.uuidString).json")
    }

    /// Environment for a box's terminal: where to report state, plus the zsh
    /// wrapper that auto-injects Claude Code hooks.
    static func environment(for id: UUID) -> [String: String] {
        try? FileManager.default.createDirectory(at: controlDir, withIntermediateDirectories: true)
        return [
            "RUNWAY_BOX": id.uuidString,
            "RUNWAY_CONTROL": file(for: id).path,
            "RUNWAY_CLAUDE_HOOKS": hooksFile.path,
            "ZDOTDIR": zdotdir.path,
        ]
    }

    static func cleanup(_ id: UUID) {
        try? FileManager.default.removeItem(at: file(for: id))
    }

    // MARK: One-time install (idempotent; call at launch)

    static func install() {
        writeHooks()
        writeZshWrapper()
    }

    private static func writeHooks() {
        func reporter(_ state: String) -> [String: Any] {
            ["hooks": [[
                "type": "command",
                "command": "[ -n \"$RUNWAY_CONTROL\" ] && printf '{\"state\":\"\(state)\"}' > \"$RUNWAY_CONTROL\"",
            ]]]
        }
        let settings: [String: Any] = ["hooks": [
            "UserPromptSubmit": [reporter("running")],
            "PreToolUse": [reporter("running")],
            "Notification": [reporter("needs-action")],
            "Stop": [reporter("idle")],
        ]]
        guard let data = try? JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted]) else { return }
        try? data.write(to: hooksFile)
    }

    private static func writeZshWrapper() {
        try? FileManager.default.createDirectory(at: zdotdir, withIntermediateDirectories: true)
        // zsh reads each startup file from $ZDOTDIR; source the user's real ones
        // so their environment is preserved, then add the claude function.
        write(".zshenv", #"[ -f "$HOME/.zshenv" ] && source "$HOME/.zshenv""#)
        write(".zprofile", #"[ -f "$HOME/.zprofile" ] && source "$HOME/.zprofile""#)
        write(".zlogin", #"[ -f "$HOME/.zlogin" ] && source "$HOME/.zlogin""#)
        write(".zshrc", """
        # Managed by Runway. Loads your real zsh config, then — only inside a Runway
        # box — routes `claude` through state-reporting hooks. Shells outside Runway
        # are unaffected; your ~/.zshrc and ~/.claude are never modified.
        [ -f "$HOME/.zshrc" ] && source "$HOME/.zshrc"
        if [ -n "$RUNWAY_CONTROL" ] && [ -n "$RUNWAY_CLAUDE_HOOKS" ]; then
          claude() { command claude --settings "$RUNWAY_CLAUDE_HOOKS" "$@"; }
        fi
        """)
    }

    private static func write(_ name: String, _ contents: String) {
        try? (contents + "\n").data(using: .utf8)?
            .write(to: zdotdir.appendingPathComponent(name))
    }
}
