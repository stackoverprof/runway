import Foundation
import GhosttyKit

/// Restarts the Claude process inside each live Runway terminal, preserving its
/// transcript id. The terminal and its workspace stay in place.
@MainActor
enum AgentSessionRestarter {
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

    private static func state(for boxID: UUID) -> String? {
        let file = AgentControl.controlDir.appendingPathComponent("\(boxID.uuidString).json")
        guard let data = try? Data(contentsOf: file),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return json["state"] as? String
    }
}
