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
    static var binDir: URL { supportDir.appendingPathComponent("bin", isDirectory: true) }
    static var integrationDir: URL { supportDir.appendingPathComponent("integration", isDirectory: true) }
    static var integrationGuide: URL { integrationDir.appendingPathComponent("SKILL.md") }

    static func file(for id: UUID) -> URL {
        controlDir.appendingPathComponent("\(id.uuidString).json")
    }

    /// Where the box's shell records its working directory (restored on relaunch).
    static func cwdFile(for id: UUID) -> URL {
        controlDir.appendingPathComponent("\(id.uuidString).cwd")
    }

    /// Environment for a box's terminal: control paths, the portable guide, and
    /// Runway-scoped command helpers.
    static func environment(for id: UUID, autorun: String? = nil) -> [String: String] {
        try? FileManager.default.createDirectory(at: controlDir, withIntermediateDirectories: true)
        let binPath = binDir.path
        let systemPath = ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        var env = [
            "RUNWAY_BOX": id.uuidString,
            "RUNWAY_CONTROL": file(for: id).path,
            "RUNWAY_FEED": feedInbox.path,
            "RUNWAY_CWD_FILE": cwdFile(for: id).path,
            "RUNWAY_CLAUDE_HOOKS": hooksFile.path,
            "ZDOTDIR": zdotdir.path,
            "RUNWAY_SKILL_PATH": integrationGuide.path,
            "RUNWAY_AGENT_GUIDE": "Run runway-help to learn Runway's terminal integration features.",
            "PATH": "\(binPath):\(systemPath)",
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
        try? FileManager.default.createDirectory(at: binDir, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: integrationDir, withIntermediateDirectories: true)
        writeHooks()
        writeFeedPostScript()
        writeZshWrapper()
        ensureFeedInbox()
        writeIntegrationGuide()
        writeBinScripts()
        cleanupLegacyGlobalInstall()
    }

    private static func writeBinScripts() {
        let postPath = binDir.appendingPathComponent("runway-post")
        let delPath = binDir.appendingPathComponent("runway-delete")
        let pinPath = binDir.appendingPathComponent("runway-pin")
        let unpinPath = binDir.appendingPathComponent("runway-unpin")
        let helpPath = binDir.appendingPathComponent("runway-help")
        let agentPath = binDir.appendingPathComponent("runway-agent")
        let claudePath = binDir.appendingPathComponent("claude")

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
          echo 'Runway API: Pin a feed post or user note to the top of the Posts tab.' >&2
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
          echo 'Runway API: Unpin a feed post or user note from the top of the Posts tab.' >&2
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

        // 6. runway-agent: opt-in coarse status reporting for any command-line agent.
        let agentScript = """
        #!/bin/zsh
        if [ "$#" -eq 0 ]; then
          echo 'Usage: runway-agent <command> [arguments…]' >&2
          exit 64
        fi
        [ -n "$RUNWAY_CONTROL" ] && printf '{"state":"running"}' > "$RUNWAY_CONTROL"
        "$@"
        exit_code=$?
        [ -n "$RUNWAY_CONTROL" ] && printf '{"state":"idle"}' > "$RUNWAY_CONTROL"
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
        "$real" --settings "$RUNWAY_CLAUDE_HOOKS" "$@"
        exit_code=$?
        [ -n "$RUNWAY_CONTROL" ] && printf '{"state":"idle"}' > "$RUNWAY_CONTROL"
        exit $exit_code
        """
        try? claudeScript.data(using: .utf8)?.write(to: claudePath)
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: claudePath.path)
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
        - `RUNWAY_FEED`: Absolute path to the timeline feed inbox JSONL file.
        - `RUNWAY_CWD_FILE`: Absolute path to the file tracking the terminal's current directory.
        - `RUNWAY_SKILL_PATH`: Path to this Runway API guide.
        - `RUNWAY_AGENT_GUIDE`: A short discovery hint for coding agents.

        ---

        ## 1. Post to the Activity Feed

        You can post markdown updates, build reports, deployment logs, or daily recaps directly to the **Posts** tab using the built-in shell helper `runway-post`.

        ### Usage
        ```bash
        # Post a simple note (author defaults to "agent")
        runway-post "Auth migration complete"

        # Post with a custom author name
        runway-post "deploy-bot" "Production deployed successfully! :rocket:"

        # Post with custom author and title
        runway-post "linter" "Found 2 warning highlights" "Style Check"

        # Post a multiline markdown document from standard input
        runway-post "analyzer" "Security Audit" - <<'EOF'
        ## Shipped Checks
        - Code injection check: **Passed**
        - Dependency audit: *0 vulnerabilities*

        Check logs for details.
        EOF
        ```

        ---

        ## 2. Delete, Pin, and Unpin Posts

        You can delete, pin, or unpin any timeline note or post by its `id` (e.g. `note-1234` or `agent-abcd`).

        ### Usage
        ```bash
        # Delete a post or note by ID
        runway-delete "note-1234"

        # Pin a post or note to the top of the Posts tab
        runway-pin "agent-5678"

        # Unpin a post or note
        runway-unpin "agent-5678"
        ```

        ---

        ## 3. Update Card Status and Metadata

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

        ### Updating Name or Description
        Write a JSON payload to `$RUNWAY_CONTROL` containing `name` and/or `description`:
        ```bash
        # Rename the terminal card title
        echo '{"name":"Build Runner"}' > "$RUNWAY_CONTROL"

        # Update the right-side gray description text
        echo '{"description":"Building release 1.0.0-beta..."}' > "$RUNWAY_CONTROL"

        # Update state, name, and description in one go
        echo '{"state":"running", "name":"Linter", "description":"Checking types..."}' > "$RUNWAY_CONTROL"
        ```
        Updates written to `$RUNWAY_CONTROL` are processed **instantly** by the app.

        ## 4. Run Any Agent With Automatic Status

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
        case ":$PATH:" in
          *":\(binDir.path):"*) ;;
          *) export PATH="\(binDir.path):$PATH" ;;
        esac
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
            echo 'Runway API: Pin a feed post or user note to the top of the Posts tab.' >&2
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
            echo 'Runway API: Unpin a feed post or user note from the top of the Posts tab.' >&2
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
