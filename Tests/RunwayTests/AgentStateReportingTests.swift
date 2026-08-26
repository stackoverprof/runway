import Foundation
import Testing
@testable import Runway

@Suite("Agent state reporting")
struct AgentStateReportingTests {
    private func command(for event: String) -> String? {
        guard let hooks = AgentControl.hookSettings["hooks"] as? [String: Any],
              let matchers = hooks[event] as? [[String: Any]],
              let first = matchers.first,
              let commands = first["hooks"] as? [[String: Any]],
              let command = commands.first?["command"] as? String else { return nil }
        return command
    }

    @Test("Finishing a turn reports needs-action at once, not idle")
    func stopMeansNeedsAction() throws {
        let stop = try #require(command(for: "Stop"))
        #expect(stop.contains("needs-action"))
        // The old mapping is what made the amber state arrive late, or never.
        #expect(!stop.contains("idle"))
    }

    @Test("Claude's own notification still reports needs-action")
    func notificationStillReports() throws {
        #expect(try #require(command(for: "Notification")).contains("needs-action"))
    }

    @Test("Work in progress reports running")
    func workReportsRunning() throws {
        for event in ["SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse"] {
            #expect(try #require(command(for: event)).contains("running"))
        }
    }

    @Test("Idle now means the session itself ended")
    func sessionEndMeansIdle() throws {
        #expect(try #require(command(for: "SessionEnd")).contains("idle"))
    }

    @Test("Every hook pulses, so Runway is woken instead of waiting for a poll")
    func everyHookPulses() throws {
        for event in [
            "SessionStart", "UserPromptSubmit", "PreToolUse",
            "PostToolUse", "Notification", "Stop", "SessionEnd",
        ] {
            #expect(try #require(command(for: event)).contains("RUNWAY_STATE_PULSE"))
        }
    }

    @Test("A terminal is told where to pulse")
    func environmentCarriesThePulsePath() {
        let env = AgentControl.environment(for: UUID())
        #expect(env["RUNWAY_STATE_PULSE"] == AgentControl.statePulse.path)
    }

    @Test("The hooks file is valid JSON for claude to read")
    func hookSettingsSerialize() {
        #expect(JSONSerialization.isValidJSONObject(AgentControl.hookSettings))
    }
}
