import SwiftUI
import Foundation

/// The agent control channel + portable integration helpers for coding agents.
///
/// - Any agent/script in a box can set its name/description/state by writing JSON
///   to `$RUNWAY_CONTROL`:  echo '{"state":"running"}' > "$RUNWAY_CONTROL"
/// - Every agent can discover the integration through `runway-help` and
///   `$RUNWAY_SKILL_PATH`; `runway-agent` adds coarse status to any CLI.
/// - Claude receives richer automatic hooks from a Runway-scoped PATH wrapper.
///   No agent-specific configuration or user shell files are modified.
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
    /// One byte appended by anything that changes an agent's state. Runway
    /// watches this single file, so a state write is noticed at once instead of
    /// on the next poll: a control file rewritten in place changes no directory
    /// entry, so the directory watcher never sees it.
    static var statePulse: URL { supportDir.appendingPathComponent("state-pulse") }

    /// Shell fragment every state writer ends with.
    static let pulseCommand = #"[ -n "$RUNWAY_STATE_PULSE" ] && printf . >> "$RUNWAY_STATE_PULSE""#

    static func ensureStatePulse() {
        try? FileManager.default.createDirectory(at: supportDir, withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: statePulse.path) {
            FileManager.default.createFile(atPath: statePulse.path, contents: nil)
        }
    }

    /// Keep the pulse file from growing forever. One byte per state change, so
    /// this trims after tens of thousands of them.
    static func trimStatePulse(largerThan limit: Int = 64 * 1024) {
        let attributes = try? FileManager.default.attributesOfItem(atPath: statePulse.path)
        let size = (attributes?[.size] as? NSNumber)?.intValue ?? 0
        guard size > limit else { return }
        try? Data().write(to: statePulse)
    }
    static var binDir: URL { supportDir.appendingPathComponent("bin", isDirectory: true) }
    static var integrationDir: URL { supportDir.appendingPathComponent("integration", isDirectory: true) }
    static var integrationGuide: URL { integrationDir.appendingPathComponent("SKILL.md") }

    /// Images Runway had to materialize from a drag that carried no file on disk.
    /// Runway's own folder, so dropping a screenshot on a terminal never leaves a
    /// second copy in ~/Downloads.
    static var dropsDir: URL {
        let dir = supportDir.appendingPathComponent("drops", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Dropped images are scratch: an agent reads one right after the drop and
    /// never again. The retention window is a setting, and can be turned off
    /// entirely, in which case nothing is pruned.
    static func pruneDrops(olderThan age: TimeInterval? = SettingsKey.dropRetention()) {
        guard let age else { return }
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: dropsDir,
            includingPropertiesForKeys: [.contentModificationDateKey]
        ) else { return }
        let cutoff = Date().addingTimeInterval(-age)
        for file in files {
            let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate
            guard let modified, modified < cutoff else { continue }
            try? FileManager.default.removeItem(at: file)
        }
    }

    static func file(for id: UUID) -> URL {
        controlDir.appendingPathComponent("\(id.uuidString).json")
    }

    /// Where the box's shell records its working directory (restored on relaunch).
    static func cwdFile(for id: UUID) -> URL {
        controlDir.appendingPathComponent("\(id.uuidString).cwd")
    }

    /// Where a Runway-scoped agent wrapper records the conversation id it bound,
    /// so the box can hand back a working resume command.
    static func sessionFile(for id: UUID) -> URL {
        controlDir.appendingPathComponent("\(id.uuidString).session")
    }

    /// Environment for a box's terminal: control paths, the portable guide, and
    /// Runway-scoped command helpers.
    static func environment(
        for id: UUID,
        autorun: String? = nil,
        focusRepository: String? = nil,
        focusIssueNumber: Int? = nil,
        issueAgentSessionsEnabled: Bool = false,
        quickTerminalSession: Bool = false
    ) -> [String: String] {
        try? FileManager.default.createDirectory(at: controlDir, withIntermediateDirectories: true)
        let binPath = binDir.path
        let systemPath = ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        var env = [
            "RUNWAY_BOX": id.uuidString,
            "RUNWAY_CONTROL": file(for: id).path,
            "RUNWAY_FOCUS_LOG": FocusActivityLog.file.path,
            "RUNWAY_CWD_FILE": cwdFile(for: id).path,
            "RUNWAY_SESSION_FILE": sessionFile(for: id).path,
            "RUNWAY_CLAUDE_HOOKS": hooksFile.path,
            "RUNWAY_STATE_PULSE": statePulse.path,
            "ZDOTDIR": zdotdir.path,
            "RUNWAY_SKILL_PATH": integrationGuide.path,
            "RUNWAY_AGENT_GUIDE": "Run runway-help for Runway integration. Focus history: runway-focus-log or $RUNWAY_FOCUS_LOG.",
            "PATH": "\(binPath):\(systemPath)",
        ]
        if let autorun, !autorun.isEmpty {
            env["RUNWAY_AUTORUN"] = scopedAutorun(autorun)
        }
        for provider in IssueAgentProvider.allCases {
            // The quick terminal's conversation is not the opt-in Focus
            // binding: keeping one session across relaunches is the panel's
            // whole point, so it is always bound.
            let sessionID: UUID? = quickTerminalSession
                ? QuickTerminalSession.id(provider: provider)
                : (issueAgentSessionsEnabled
                    ? IssueAgentSession.id(
                        provider: provider,
                        repository: focusRepository,
                        issueNumber: focusIssueNumber
                    )
                    : nil)
            guard let sessionID else { continue }
            let prefix = "RUNWAY_\(provider.rawValue.uppercased())_SESSION"
            env["\(prefix)_ID"] = sessionID.uuidString.lowercased()
        }
        return env
    }

    /// Resolve supported configured agents directly through Runway's adapter.
    /// This avoids aliases and zsh's command hash bypassing the scoped PATH entry.
    static func scopedAutorun(_ command: String) -> String {
        for provider in IssueAgentProvider.allCases {
            let name = provider.rawValue
            guard command == name || command.hasPrefix("\(name) ") else { continue }
            let executable = binDir.appendingPathComponent(name).path
            let quoted = "'\(executable.replacingOccurrences(of: "'", with: "'\\''"))'"
            return quoted + command.dropFirst(name.count)
        }
        return command
    }

    static func cleanup(_ id: UUID) {
        try? FileManager.default.removeItem(at: file(for: id))
        try? FileManager.default.removeItem(at: cwdFile(for: id))
        try? FileManager.default.removeItem(at: sessionFile(for: id))
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
        try? FileManager.default.createDirectory(at: binDir, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: integrationDir, withIntermediateDirectories: true)
        FocusActivityLog.ensureFile()
        ensureStatePulse()
        writeHooks()
        writeZshWrapper()
        writeIntegrationGuide()
        writeBinScripts()
        removeNotesHelpers()
        cleanupLegacyGlobalInstall()
    }

    private static func removeNotesHelpers() {
        for name in ["runway-post", "runway-delete", "runway-pin", "runway-unpin"] {
            try? FileManager.default.removeItem(at: binDir.appendingPathComponent(name))
        }
        try? FileManager.default.removeItem(at: feedPostScript)
    }

    private static func writeBinScripts() {
        let postPath = binDir.appendingPathComponent("runway-post")
        let delPath = binDir.appendingPathComponent("runway-delete")
        let pinPath = binDir.appendingPathComponent("runway-pin")
        let unpinPath = binDir.appendingPathComponent("runway-unpin")
        let helpPath = binDir.appendingPathComponent("runway-help")
        let focusLogPath = binDir.appendingPathComponent("runway-focus-log")
        let agentPath = binDir.appendingPathComponent("runway-agent")
        let claudePath = binDir.appendingPathComponent("claude")
        let geminiPath = binDir.appendingPathComponent("gemini")

        // 1. runway-post
        let postScript = """
        #!/usr/bin/env python3
        import sys, os, json, datetime
        
        def main():
            args = sys.argv[1:]
            if "-h" in args or "--help" in args:
                print("Runway API: Post a note or post to the activity feed.", file=sys.stderr)
                print("Usage:", file=sys.stderr)
                print("  runway-post \\"body text\\"                       (author: agent)", file=sys.stderr)
                print("  runway-post \\"author_name\\" \\"body text\\"         (custom author)", file=sys.stderr)
                print("  runway-post \\"author_name\\" \\"body text\\" \\"title\\" (custom title)", file=sys.stderr)
                print("  runway-post \\"author_name\\" \\"title\\" - <<EOF     (multiline stdin)", file=sys.stderr)
                sys.exit(0)
            
            feed = os.environ.get("RUNWAY_FEED")
            if not feed:
                print("runway-post: not in a Runway terminal (RUNWAY_FEED unset)", file=sys.stderr)
                sys.exit(1)

            def unesc(s):
                return s.replace('\\\\n', '\\n').replace('\\\\t', '\\t')

            stdin_body = ""
            if args and args[-1] == "-":
                stdin_body = sys.stdin.read()
                args = args[:-1]

            if stdin_body:
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
            
            payload = {
                "author": author,
                "title": title,
                "body": body,
                "date": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
            }
            with open(feed, "a") as f:
                f.write(json.dumps(payload) + "\\n")

        if __name__ == "__main__":
            main()
        """
        try? postScript.data(using: .utf8)?.write(to: postPath)
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: postPath.path)

        // 2. runway-delete
        let delScript = """
        #!/bin/zsh
        if [ "$1" = "-h" ] || [ "$1" = "--help" ] || [ -z "$1" ]; then
          echo 'Runway API: Delete a feed post or user note by ID.' >&2
          echo 'Usage:' >&2
          echo '  runway-delete <post_id_or_note_id>   (e.g., note-1234 or agent-abcd)' >&2
          exit 0
        fi
        if [ -z "$RUNWAY_FEED" ]; then
          echo 'runway-delete: not in a Runway terminal (RUNWAY_FEED unset)' >&2
          exit 1
        fi
        echo "{\\"action\\":\\"delete\\",\\"id\\":\\"$1\\"}" >> "$RUNWAY_FEED"
        """
        try? delScript.data(using: .utf8)?.write(to: delPath)
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: delPath.path)

        // 3. runway-pin
        let pinScript = """
        #!/bin/zsh
        if [ "$1" = "-h" ] || [ "$1" = "--help" ] || [ -z "$1" ]; then
          echo 'Runway API: Pin a feed post or user note to the top of the Notes tab.' >&2
          echo 'Usage:' >&2
          echo '  runway-pin <post_id_or_note_id>      (e.g., note-1234 or agent-abcd)' >&2
          exit 0
        fi
        if [ -z "$RUNWAY_FEED" ]; then
          echo 'runway-pin: not in a Runway terminal (RUNWAY_FEED unset)' >&2
          exit 1
        fi
        echo "{\\"action\\":\\"pin\\",\\"id\\":\\"$1\\"}" >> "$RUNWAY_FEED"
        """
        try? pinScript.data(using: .utf8)?.write(to: pinPath)
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: pinPath.path)

        // 4. runway-unpin
        let unpinScript = """
        #!/bin/zsh
        if [ "$1" = "-h" ] || [ "$1" = "--help" ] || [ -z "$1" ]; then
          echo 'Runway API: Unpin a feed post or user note from the top of the Notes tab.' >&2
          echo 'Usage:' >&2
          echo '  runway-unpin <post_id_or_note_id>    (e.g., note-1234 or agent-abcd)' >&2
          exit 0
        fi
        if [ -z "$RUNWAY_FEED" ]; then
          echo 'runway-unpin: not in a Runway terminal (RUNWAY_FEED unset)' >&2
          exit 1
        fi
        echo "{\\"action\\":\\"unpin\\",\\"id\\":\\"$1\\"}" >> "$RUNWAY_FEED"
        """
        try? unpinScript.data(using: .utf8)?.write(to: unpinPath)
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: unpinPath.path)

        // 5. runway-help: one discovery point that works for every coding agent.
        let helpScript = """
        #!/bin/zsh
        exec /bin/cat "${RUNWAY_SKILL_PATH:-\(integrationGuide.path)}"
        """
        try? helpScript.data(using: .utf8)?.write(to: helpPath)
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: helpPath.path)

        let focusLogScript = """
        #!/bin/zsh
        exec /bin/cat "${RUNWAY_FOCUS_LOG:-\(FocusActivityLog.file.path)}"
        """
        try? focusLogScript.data(using: .utf8)?.write(to: focusLogPath)
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: focusLogPath.path)

        // 6. runway-agent: opt-in coarse status reporting for any command-line agent.
        let agentScript = """
        #!/bin/zsh
        if [ "$#" -eq 0 ]; then
          echo 'Usage: runway-agent <command> [arguments…]' >&2
          exit 64
        fi
        [ -n "$RUNWAY_CONTROL" ] && printf '{"state":"running"}' > "$RUNWAY_CONTROL"
        \(pulseCommand)
        "$@"
        exit_code=$?
        [ -n "$RUNWAY_CONTROL" ] && printf '{"state":"idle"}' > "$RUNWAY_CONTROL"
        \(pulseCommand)
        exit $exit_code
        """
        try? agentScript.data(using: .utf8)?.write(to: agentPath)
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: agentPath.path)

        // Preserve Claude's richer needs-action hooks without replacing a user's
        // alias or shell function. This PATH wrapper is scoped to Runway terminals.
        let claudeScript = """
        #!/bin/zsh
        wrapper_dir="${0:A:h}"
        real=""
        for dir in "${(@s/:/)PATH}"; do
          [ "$dir" = "$wrapper_dir" ] && continue
          if [ -x "$dir/claude" ]; then real="$dir/claude"; break; fi
        done
        if [ -z "$real" ]; then
          echo 'claude: command not found' >&2
          exit 127
        fi
        explicit_session=0
        for arg in "$@"; do
          case "$arg" in
            -c|--continue|-r|--resume|--resume=*|--session-id|--session-id=*|--fork-session)
              explicit_session=1
              break
              ;;
          esac
        done
        session_args=()
        session_mode="unbound"
        if [ "$explicit_session" -eq 0 ] && [ -n "$RUNWAY_CLAUDE_SESSION_ID" ]; then
          transcript=""
          if [ -d "$HOME/.claude/projects" ]; then
            transcript=$(/usr/bin/find "$HOME/.claude/projects" -type f -name "$RUNWAY_CLAUDE_SESSION_ID.jsonl" -print -quit 2>/dev/null)
          fi
          if [ -n "$transcript" ]; then
            session_args=(--resume "$RUNWAY_CLAUDE_SESSION_ID")
            session_mode="resume"
          else
            session_args=(--session-id "$RUNWAY_CLAUDE_SESSION_ID")
            session_mode="create"
          fi
        elif [ "$explicit_session" -eq 1 ]; then
          session_mode="explicit"
        fi
        export RUNWAY_CLAUDE_SESSION_MODE="$session_mode"
        if [ -n "$RUNWAY_SESSION_FILE" ] && [ -n "$RUNWAY_CLAUDE_SESSION_ID" ] && [ "$explicit_session" -eq 0 ]; then
          printf '{"provider":"claude","sessionId":"%s"}' "$RUNWAY_CLAUDE_SESSION_ID" > "$RUNWAY_SESSION_FILE"
        fi
        "$real" --settings "$RUNWAY_CLAUDE_HOOKS" "${session_args[@]}" "$@"
        exit_code=$?
        [ -n "$RUNWAY_CONTROL" ] && printf '{"state":"idle"}' > "$RUNWAY_CONTROL"
        \(pulseCommand)
        exit $exit_code
        """
        try? claudeScript.data(using: .utf8)?.write(to: claudePath)
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: claudePath.path)

        // Gemini also supports caller-assigned session UUIDs. This wrapper uses
        // the same issue-owned identity while preserving explicit user flags.
        let geminiScript = """
        #!/bin/zsh
        wrapper_dir="${0:A:h}"
        real=""
        for dir in "${(@s/:/)PATH}"; do
          [ "$dir" = "$wrapper_dir" ] && continue
          if [ -x "$dir/gemini" ]; then real="$dir/gemini"; break; fi
        done
        if [ -z "$real" ]; then
          echo 'gemini: command not found' >&2
          exit 127
        fi
        explicit_session=0
        for arg in "$@"; do
          case "$arg" in
            -r|--resume|--resume=*|--session-id|--session-id=*|--session-file|--session-file=*)
              explicit_session=1
              break
              ;;
          esac
        done
        session_args=()
        session_mode="unbound"
        if [ "$explicit_session" -eq 0 ] && [ -n "$RUNWAY_GEMINI_SESSION_ID" ]; then
          short_id="${RUNWAY_GEMINI_SESSION_ID[1,8]}"
          transcript=""
          if [ -d "$HOME/.gemini/tmp" ]; then
            transcript=$(/usr/bin/find "$HOME/.gemini/tmp" -type f -path '*/chats/*' \\( -name "*-$short_id.json" -o -name "*-$short_id.jsonl" \\) -print -quit 2>/dev/null)
          fi
          if [ -n "$transcript" ]; then
            session_args=(--resume "$RUNWAY_GEMINI_SESSION_ID")
            session_mode="resume"
          else
            session_args=(--session-id "$RUNWAY_GEMINI_SESSION_ID")
            session_mode="create"
          fi
        elif [ "$explicit_session" -eq 1 ]; then
          session_mode="explicit"
        fi
        export RUNWAY_GEMINI_SESSION_MODE="$session_mode"
        if [ -n "$RUNWAY_SESSION_FILE" ] && [ -n "$RUNWAY_GEMINI_SESSION_ID" ] && [ "$explicit_session" -eq 0 ]; then
          printf '{"provider":"gemini","sessionId":"%s"}' "$RUNWAY_GEMINI_SESSION_ID" > "$RUNWAY_SESSION_FILE"
        fi
        [ -n "$RUNWAY_CONTROL" ] && printf '{"state":"running"}' > "$RUNWAY_CONTROL"
        \(pulseCommand)
        "$real" "${session_args[@]}" "$@"
        exit_code=$?
        [ -n "$RUNWAY_CONTROL" ] && printf '{"state":"idle"}' > "$RUNWAY_CONTROL"
        \(pulseCommand)
        exit $exit_code
        """
        try? geminiScript.data(using: .utf8)?.write(to: geminiPath)
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: geminiPath.path)
    }

    private static func ensureFeedInbox() {
        if !FileManager.default.fileExists(atPath: feedInbox.path) {
            FileManager.default.createFile(atPath: feedInbox.path, contents: nil)
        }
    }

    private static func writeHooks() {
        guard let data = try? JSONSerialization.data(
            withJSONObject: hookSettings,
            options: [.prettyPrinted]
        ) else { return }
        try? data.write(to: hooksFile)
    }

    /// The claude settings Runway hands its wrapper. Separated from the write so
    /// the state each hook reports can be asserted.
    static var hookSettings: [String: Any] {
        func reporter(_ state: String) -> [String: Any] {
            return ["hooks": [[
                "type": "command",
                "command": "[ -n \"$RUNWAY_CONTROL\" ] && printf '{\"state\":\"\(state)\"}' > \"$RUNWAY_CONTROL\"; \(pulseCommand); true",
            ]]]
        }
        // Stop is the moment the agent stops working and hands the turn back,
        // which is exactly when it needs the user: it reports needs-action, not
        // idle. Waiting for Claude's own Notification hook is what made the
        // amber state arrive a minute late, or not at all. Idle now means the
        // session itself ended.
        let settings: [String: Any] = ["hooks": [
            "SessionStart": [reporter("running")],
            "UserPromptSubmit": [reporter("running")],
            "PreToolUse": [reporter("running")],
            "PostToolUse": [reporter("running")],
            "Notification": [reporter("needs-action")],
            "Stop": [reporter("needs-action")],
            "SessionEnd": [reporter("idle")],
        ]]
        return settings
    }

    private static func writeIntegrationGuide() {
        let markdown = """
        ---
        name: runway-app-integration
        description: Harness Runway terminal features from any coding agent or shell.
        ---

        # Runway Integration Skill

        This portable guide is available to every coding agent and shell running
        inside Runway. Run `runway-help` at any time to read it. No agent-specific
        files are installed in your home directory.

        ## Environment Variables

        Each Runway terminal box exposes the following environment variables to its shell:
        - `RUNWAY_BOX`: The unique UUID of the terminal card.
        - `RUNWAY_CONTROL`: Absolute path to a JSON file controlling the card's metadata and state.
        - `RUNWAY_FOCUS_LOG`: Append-only JSONL history of issues entering and leaving Focus.
        - `RUNWAY_CWD_FILE`: Absolute path to the file tracking the terminal's current directory.
        - `RUNWAY_STATE_PULSE`: Append one byte here after writing state (`printf . >> "$RUNWAY_STATE_PULSE"`). Runway watches this single file, so the card updates at once instead of on the next poll.
        - `RUNWAY_SESSION_FILE`: Where Runway's scoped wrappers record the conversation id they bound, so the terminal can offer a resume command.
        - `RUNWAY_SKILL_PATH`: Path to this Runway API guide.
        - `RUNWAY_AGENT_GUIDE`: A short discovery hint for coding agents.
        - `RUNWAY_CLAUDE_SESSION_ID` / `RUNWAY_GEMINI_SESSION_ID`: Stable provider conversation IDs. Focus terminals expose them while Focus conversation binding is enabled in Settings (on by default); the quick terminal always carries its own kept conversation, rotated only by the `+` button in its header. Runway's scoped wrappers use them to create or resume the bound conversation. This is tested with Claude only; other agents and models are untested.

        ---

        ## 1. Update Card Status and Metadata

        You can dynamically update the card's **State Dot (color)**, **Title**, and **Description** at any time.

        ### Updating State
        To change the colored dot next to your terminal card, write a JSON payload to `$RUNWAY_CONTROL`:
        ```bash
        # Set status to active/busy (Green dot)
        echo '{"state":"running"}' > "$RUNWAY_CONTROL"

        # Set status to needs attention (Amber dot)
        echo '{"state":"needs-action"}' > "$RUNWAY_CONTROL"

        # Set status back to idle (Grey dot)
        echo '{"state":"idle"}' > "$RUNWAY_CONTROL"
        ```

        Runway notices a state write on its next poll, up to 1.5 seconds later.
        To have the card update at once, append one byte to the pulse file after
        writing state:
        ```bash
        echo '{"state":"needs-action"}' > "$RUNWAY_CONTROL"
        printf . >> "$RUNWAY_STATE_PULSE"
        ```

        ### Updating Name or Description
        Write a JSON payload to `$RUNWAY_CONTROL` containing `name` and/or `description`:
        ```bash
        # Rename the terminal card title
        echo '{"name":"Build Runner"}' > "$RUNWAY_CONTROL"

        # Update the right-side gray description text
        echo '{"description":"Building release 2.0.0..."}' > "$RUNWAY_CONTROL"

        # Update state, name, and description in one go
        echo '{"state":"running", "name":"Linter", "description":"Checking types..."}' > "$RUNWAY_CONTROL"
        ```
        Updates written to `$RUNWAY_CONTROL` are processed **instantly** by the app.
        Focus terminal names and descriptions are issue-owned and read-only. For those
        cards, metadata writes are ignored, the description shows the issue reference
        such as `#1234`, and clicking it copies that reference. State updates still apply.

        ## 2. Read Focus Work History

        Runway appends one JSON object to `$RUNWAY_FOCUS_LOG` whenever an issue
        enters or leaves the Focus board. Reordering within Focus is not logged.
        Each event includes an ISO-8601 `timestamp`, IANA `timeZone`, `action`, `repository`,
        `issueNumber`, `issueTitle`, `issueState`, `fromLane`, `toLane`, and `cause`.

        ```bash
        # Read the complete journal
        runway-focus-log

        # Select an exact UTC time range
        jq -c 'select(.timestamp >= "2026-07-29T08:43:00Z" and .timestamp <= "2026-07-30T05:00:00Z")' "$RUNWAY_FOCUS_LOG"
        ```

        Pair `entered_focus` and `exited_focus` events by repository and issue
        number to reconstruct work sessions. An entry with
        `cause: "initial_snapshot"` marks an issue that was already focused when
        logging began. `cause: "github_rollback"` compensates for a move that
        GitHub rejected.

        ## 3. Run Any Agent With Automatic Status

        Use `runway-agent` with any command-line coding agent to mark the card
        running until the command exits:

        ```bash
        runway-agent codex
        runway-agent gemini
        runway-agent my-custom-agent --flag
        ```

        Claude receives richer automatic status hooks when launched normally as
        `claude` inside Runway.
        """

        try? markdown.write(to: integrationGuide, atomically: true, encoding: .utf8)
    }

    /// Remove only files written by older Runway builds. Parent directories are
    /// removed only when empty, so unrelated user configuration is untouched.
    private static func cleanupLegacyGlobalInstall() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let legacyBin = home.appendingPathComponent(".runway/bin", isDirectory: true)
        for name in ["runway-post", "runway-delete", "runway-pin", "runway-unpin"] {
            try? FileManager.default.removeItem(at: legacyBin.appendingPathComponent(name))
        }
        try? FileManager.default.removeItem(at: legacyBin)

        let legacySkillDir = home.appendingPathComponent(".gemini/config/skills/runway_api", isDirectory: true)
        try? FileManager.default.removeItem(at: legacySkillDir.appendingPathComponent("SKILL.md"))
        try? FileManager.default.removeItem(at: legacySkillDir)
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
        // so their environment and prompt remain unchanged. Agent integration is
        // provided by scoped PATH helpers instead of replacing shell functions.
        write(".zshenv", #"[ -f "$HOME/.zshenv" ] && source "$HOME/.zshenv""#)
        write(".zprofile", #"[ -f "$HOME/.zprofile" ] && source "$HOME/.zprofile""#)
        write(".zlogin", #"[ -f "$HOME/.zlogin" ] && source "$HOME/.zlogin""#)
        write(".zshrc", """
        # Managed by Runway. Loads your real zsh config and adds only Runway's
        # working-directory and autorun hooks. Your files are never modified.
        [ -f "$HOME/.zshrc" ] && source "$HOME/.zshrc"
        # The user's own config is sourced first and commonly prepends its own
        # bin directories, which would shadow Runway's scoped wrappers. Move
        # Runway's entry back to the front instead of merely ensuring it is
        # present, so `claude` in a Runway terminal is always the wrapper.
        runway_bin='\(binDir.path)'
        path=("$runway_bin" "${(@)path:#${runway_bin}}")
        export PATH
        unset runway_bin
        hash -r 2>/dev/null || true
        # Post a markdown card to the activity timeline.
        runway-post() {
          if [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
            echo 'Runway API: Post a note or post to the activity feed.' >&2
            echo 'Usage:' >&2
            echo '  runway-post "body text"                       (author: agent)' >&2
            echo '  runway-post "author_name" "body text"         (custom author)' >&2
            echo '  runway-post "author_name" "body text" "title" (custom title)' >&2
            echo '  runway-post "author_name" "title" - <<EOF     (multiline stdin)' >&2
            return 0
          fi
          if [ -z "$RUNWAY_FEED" ]; then
            echo 'runway-post: not in a Runway terminal (RUNWAY_FEED unset)' >&2
            echo '  Use Runway quick terminal (⌘⌥Q) or an agent card.' >&2
            return 1
          fi
          python3 '\(postScript)' "$@" >> "$RUNWAY_FEED"
        }
        # Delete a post or note by ID.
        runway-delete() {
          if [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
            echo 'Runway API: Delete a feed post or user note by ID.' >&2
            echo 'Usage:' >&2
            echo '  runway-delete <post_id_or_note_id>   (e.g., note-1234 or agent-abcd)' >&2
            return 0
          fi
          if [ -z "$RUNWAY_FEED" ]; then
            echo 'runway-delete: not in a Runway terminal (RUNWAY_FEED unset)' >&2
            return 1
          fi
          if [ -z "$1" ]; then
            echo 'Usage: runway-delete <post_id>' >&2
            return 1
          fi
          echo "{\\"action\\":\\"delete\\",\\"id\\":\\"$1\\"}" >> "$RUNWAY_FEED"
        }
        # Pin a post or note by ID.
        runway-pin() {
          if [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
            echo 'Runway API: Pin a feed post or user note to the top of the Notes tab.' >&2
            echo 'Usage:' >&2
            echo '  runway-pin <post_id_or_note_id>      (e.g., note-1234 or agent-abcd)' >&2
            return 0
          fi
          if [ -z "$RUNWAY_FEED" ]; then
            echo 'runway-pin: not in a Runway terminal (RUNWAY_FEED unset)' >&2
            return 1
          fi
          if [ -z "$1" ]; then
            echo 'Usage: runway-pin <post_id>' >&2
            return 1
          fi
          echo "{\\"action\\":\\"pin\\",\\"id\\":\\"$1\\"}" >> "$RUNWAY_FEED"
        }
        # Unpin a post or note by ID.
        runway-unpin() {
          if [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
            echo 'Runway API: Unpin a feed post or user note from the top of the Notes tab.' >&2
            echo 'Usage:' >&2
            echo '  runway-unpin <post_id_or_note_id>    (e.g., note-1234 or agent-abcd)' >&2
            return 0
          fi
          if [ -z "$RUNWAY_FEED" ]; then
            echo 'runway-unpin: not in a Runway terminal (RUNWAY_FEED unset)' >&2
            return 1
          fi
          if [ -z "$1" ]; then
            echo 'Usage: runway-unpin <post_id>' >&2
            return 1
          fi
          echo "{\\"action\\":\\"unpin\\",\\"id\\":\\"$1\\"}" >> "$RUNWAY_FEED"
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
