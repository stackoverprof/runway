import SwiftUI
import Foundation

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

    static var feedDir: URL {
        let dir = supportDir.appendingPathComponent("feed", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
    static var feedInbox: URL { feedDir.appendingPathComponent("inbox.jsonl") }
    static var feedPostScript: URL { supportDir.appendingPathComponent("feed-post.py") }
    static var controlDir: URL { supportDir.appendingPathComponent("control", isDirectory: true) }
    static var zdotdir: URL { supportDir.appendingPathComponent("zsh", isDirectory: true) }
    static var hooksFile: URL { supportDir.appendingPathComponent("claude-hooks.json") }

    static func file(for id: UUID) -> URL {
        controlDir.appendingPathComponent("\(id.uuidString).json")
    }

    /// Where the box's shell records its working directory (restored on relaunch).
    static func cwdFile(for id: UUID) -> URL {
        controlDir.appendingPathComponent("\(id.uuidString).cwd")
    }

    /// Environment for a box's terminal: where to report state, plus the zsh
    /// wrapper that auto-injects Claude Code hooks.
    static func environment(for id: UUID, autorun: String? = nil) -> [String: String] {
        try? FileManager.default.createDirectory(at: controlDir, withIntermediateDirectories: true)
        var env = [
            "RUNWAY_BOX": id.uuidString,
            "RUNWAY_CONTROL": file(for: id).path,
            "RUNWAY_FEED": feedInbox.path,
            "RUNWAY_CWD_FILE": cwdFile(for: id).path,
            "RUNWAY_CLAUDE_HOOKS": hooksFile.path,
            "ZDOTDIR": zdotdir.path,
        ]
        if let autorun, !autorun.isEmpty { env["RUNWAY_AUTORUN"] = autorun }
        return env
    }

    static func cleanup(_ id: UUID) {
        try? FileManager.default.removeItem(at: file(for: id))
        try? FileManager.default.removeItem(at: cwdFile(for: id))
    }

    /// Clear stale agent states at launch: the shells start fresh (nothing running
    /// yet), so any leftover state file from a previous session is bogus.
    static func resetStates() {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: controlDir, includingPropertiesForKeys: nil) else { return }
        for f in files where f.pathExtension == "json" { try? FileManager.default.removeItem(at: f) }
    }

    // MARK: One-time install (idempotent; call at launch)

    static func install() {
        writeHooks()
        writeFeedPostScript()
        writeZshWrapper()
        ensureFeedInbox()
    }

    private static func ensureFeedInbox() {
        if !FileManager.default.fileExists(atPath: feedInbox.path) {
            FileManager.default.createFile(atPath: feedInbox.path, contents: nil)
        }
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

    private static func writeFeedPostScript() {
        // Standalone script — avoids Swift→zsh→python escape corruption.
        let py = """
        #!/usr/bin/env python3
        import json, sys, datetime

        def unesc(s):
            if not s:
                return s
            return (s.replace("\\\\n", chr(10))
                     .replace("\\\\t", chr(9))
                     .replace("\\\\r", chr(13)))

        def main():
            args = sys.argv[1:]
            stdin_body = None
            if args and args[-1] == "-":
                stdin_body = sys.stdin.read()
                args = args[:-1]

            if stdin_body is not None:
                if len(args) == 0:
                    author, title = "agent", ""
                elif len(args) == 1:
                    author, title = args[0], ""
                else:
                    author, title = args[0], args[1]
                body = stdin_body
            elif len(args) == 0:
                return
            elif len(args) == 1:
                author, title, body = "agent", "", args[0]
            elif len(args) == 2:
                author, title, body = args[0], "", args[1]
            else:
                author, body, title = args[0], args[1], args[2]

            title = unesc(title)
            body = unesc(body)
            if not body.strip():
                return
            print(json.dumps({
                "author": author,
                "title": title,
                "body": body,
                "date": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
            }))

        if __name__ == "__main__":
            main()
        """
        try? py.data(using: .utf8)?.write(to: feedPostScript)
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: feedPostScript.path)
    }

    private static func writeZshWrapper() {
        try? FileManager.default.createDirectory(at: zdotdir, withIntermediateDirectories: true)
        let postScript = feedPostScript.path
        // zsh reads each startup file from $ZDOTDIR; source the user's real ones
        // so their environment is preserved, then add the claude function.
        write(".zshenv", #"[ -f "$HOME/.zshenv" ] && source "$HOME/.zshenv""#)
        write(".zprofile", #"[ -f "$HOME/.zprofile" ] && source "$HOME/.zprofile""#)
        write(".zlogin", #"[ -f "$HOME/.zlogin" ] && source "$HOME/.zlogin""#)
        write(".zshrc", """
        # Managed by Runway. Loads your real zsh config, then (only inside a Runway
        # box) routes `claude` through state-reporting hooks. Shells outside Runway
        # are unaffected; your ~/.zshrc and ~/.claude are never modified.
        [ -f "$HOME/.zshrc" ] && source "$HOME/.zshrc"
        if [ -n "$RUNWAY_CONTROL" ] && [ -n "$RUNWAY_CLAUDE_HOOKS" ]; then
          claude() {
            command claude --settings "$RUNWAY_CLAUDE_HOOKS" "$@"
            # Back at the shell prompt: the agent is no longer running.
            printf '{"state":"idle"}' > "$RUNWAY_CONTROL"
          }
        fi
        # Post a markdown card to the activity timeline.
        #   runway-post "body"                       (author: agent)
        #   runway-post author "body"              (no title)
        #   runway-post author "body" "title"
        #   runway-post author "title" - <<'EOF'   (multiline body from stdin)
        runway-post() {
          if [ -z "$RUNWAY_FEED" ]; then
            echo 'runway-post: not in a Runway terminal (RUNWAY_FEED unset)' >&2
            echo '  Use Runway quick terminal (⌘⌥Q) or an agent card.' >&2
            return 1
          fi
          python3 '\(postScript)' "$@" >> "$RUNWAY_FEED"
        }
        # Record the working directory so Runway can reopen each agent in the same
        # folder after a relaunch (written at startup, on cd, and at each prompt).
        if [ -n "$RUNWAY_CWD_FILE" ]; then
          _runway_cwd() { pwd > "$RUNWAY_CWD_FILE" 2>/dev/null; }
          autoload -Uz add-zsh-hook 2>/dev/null
          add-zsh-hook chpwd _runway_cwd 2>/dev/null
          add-zsh-hook precmd _runway_cwd 2>/dev/null
          _runway_cwd
        fi
        # New agents open straight into a command (e.g. claude). Runs once, before
        # the first prompt, so the agent is up the moment the card appears; you
        # drop to the shell when it exits.
        if [ -n "$RUNWAY_AUTORUN" ]; then
          _cmd="$RUNWAY_AUTORUN"; unset RUNWAY_AUTORUN
          eval "$_cmd"
        fi
        """)
    }

    private static func write(_ name: String, _ contents: String) {
        try? (contents + "\n").data(using: .utf8)?
            .write(to: zdotdir.appendingPathComponent(name))
    }
}
