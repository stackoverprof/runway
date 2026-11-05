import Foundation
import GhosttyKit

/// Restarts the Claude process inside each live Runway terminal, preserving its
/// transcript id. The terminal and its workspace stay in place.
@MainActor
enum AgentSessionRestarter {
    struct FullscreenResult {
        var sent = 0
        var untracked = 0
        var busy = 0
        var promptOccupied = 0
    }

    static func setFullscreenWhenReady(
        _ session: GhosttyTerminalSession,
        boxID: UUID,
        timeout: TimeInterval = 30
    ) async {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline, !Task.isCancelled {
            if AgentSessionLocator.recorded(for: boxID)?.provider == .claude,
               isIdle(boxID), isEmptyClaudePrompt(session) {
                session.insertText("/tui fullscreen\r")
                return
            }
            try? await Task.sleep(nanoseconds: 500_000_000)
        }
    }

    static func setAllIdleSessionsToFullscreen() -> FullscreenResult {
        var result = FullscreenResult()
        for session in RunwayTerminalSessions.live() {
            guard let boxID = RunwayTerminalSessions.boxID(for: session) else {
                result.untracked += 1
                continue
            }
            guard isIdle(boxID) else {
                result.busy += 1
                continue
            }
            guard isEmptyClaudePrompt(session) else {
                result.promptOccupied += 1
                continue
            }
            session.insertText("/tui fullscreen\r")
            result.sent += 1
        }
        return result
    }

    static func restartAll(on model: String) async -> Int {
        let model = model.trimmingCharacters(in: .whitespacesAndNewlines)

        var restarted = 0
        var handled = Set<UUID>()
        for session in RunwayTerminalSessions.live() {
            guard let boxID = RunwayTerminalSessions.boxID(for: session),
                  handled.insert(boxID).inserted else { continue }
            let conversation = AgentSessionLocator.recorded(for: boxID)
            guard let conversation, conversation.provider == .claude else { continue }
            let shouldContinue = isRunning(boxID)

            // Ctrl-C twice stops a running Claude turn and exits Claude from an
            // idle prompt. The wrapper then resumes the same transcript.
            session.insertText("\u{03}")
            try? await Task.sleep(nanoseconds: 300_000_000)
            session.insertText("\u{03}")
            try? await Task.sleep(nanoseconds: 500_000_000)

            let resume = " --resume \(shellQuote(conversation.sessionID))"
            let continuation = shouldContinue
                ? " \(shellQuote("Continue the work that was interrupted when Runway restarted this session."))"
                : ""
            let modelArgument = model.isEmpty ? "" : " --model \(shellQuote(model))"
            session.insertText("claude\(resume)\(modelArgument)\(continuation)\r")
            restarted += 1
        }
        return restarted
    }

    private static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private static func isRunning(_ boxID: UUID) -> Bool {
        state(for: boxID) == "running"
    }

    private static func isIdle(_ boxID: UUID) -> Bool {
        state(for: boxID) == "idle"
    }

    private static func state(for boxID: UUID) -> String? {
        let file = AgentControl.controlDir.appendingPathComponent("\(boxID.uuidString).json")
        guard let data = try? Data(contentsOf: file),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return json["state"] as? String
    }

    /// Never type a slash command into an agent's existing prompt text. Only
    /// act when the visible terminal ends at a known, empty Claude prompt.
    private static func isEmptyClaudePrompt(_ session: GhosttyTerminalSession) -> Bool {
        guard let surface = session.surface else { return false }
        var text = ghostty_text_s()
        let visible = ghostty_selection_s(
            top_left: ghostty_point_s(
                tag: GHOSTTY_POINT_SCREEN,
                coord: GHOSTTY_POINT_COORD_TOP_LEFT,
                x: 0,
                y: 0
            ),
            bottom_right: ghostty_point_s(
                tag: GHOSTTY_POINT_SCREEN,
                coord: GHOSTTY_POINT_COORD_BOTTOM_RIGHT,
                x: 0,
                y: 0
            ),
            rectangle: false
        )
        guard ghostty_surface_read_text(surface, visible, &text) else { return false }
        defer { ghostty_surface_free_text(surface, &text) }
        let screen = String(cString: text.text)
        // Claude paints status/help rows after its input row. Look in the
        // bottom of the viewport for the last *empty* prompt marker instead
        // of assuming that the screen's final nonblank line is the prompt.
        let promptRows = screen
            .split(whereSeparator: \.isNewline)
            .suffix(16)
            .map { row in
                String(row.unicodeScalars.filter { scalar in
                    !CharacterSet.whitespacesAndNewlines.contains(scalar)
                        && scalar.value != 0x200B // zero-width space
                        && scalar.value != 0xFEFF // zero-width no-break space
                        && scalar.properties.generalCategory != .format
                })
            }
        return promptRows.contains { ["❯", ">", "›"].contains($0) }
    }
}
