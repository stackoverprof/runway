import Foundation
import Testing
@testable import Runway

@Suite("Issue agent sessions")
struct IssueAgentSessionTests {
    @Test("An issue always receives the same provider session")
    func stableIdentity() {
        let first = IssueAgentSession.id(
            provider: .claude,
            repository: "VISKA-IO/monorepo",
            issueNumber: 10388
        )
        let second = IssueAgentSession.id(
            provider: .claude,
            repository: "viska-io/MONOREPO",
            issueNumber: 10388
        )

        #expect(first == second)
        #expect(first.uuidString.split(separator: "-")[2].first == "4")
    }

    @Test("Providers, repositories, and issues have separate sessions")
    func distinctIdentities() {
        let original = IssueAgentSession.id(
            provider: .claude,
            repository: "VISKA-IO/monorepo",
            issueNumber: 10388
        )

        #expect(original != IssueAgentSession.id(
            provider: .gemini,
            repository: "VISKA-IO/monorepo",
            issueNumber: 10388
        ))
        #expect(original != IssueAgentSession.id(
            provider: .claude,
            repository: "VISKA-IO/another-repo",
            issueNumber: 10388
        ))
        #expect(original != IssueAgentSession.id(
            provider: .claude,
            repository: "VISKA-IO/monorepo",
            issueNumber: 10389
        ))
    }

    @Test("Non-Focus terminals do not receive provider sessions")
    func unmanagedTerminalHasNoIdentity() {
        #expect(IssueAgentSession.id(
            provider: .claude,
            repository: nil,
            issueNumber: nil
        ) == nil)
    }

    @Test("Focus terminal environment exposes provider bindings")
    func focusTerminalEnvironment() {
        let environment = AgentControl.environment(
            for: UUID(),
            focusRepository: "VISKA-IO/monorepo",
            focusIssueNumber: 10388,
            issueAgentSessionsEnabled: true
        )

        #expect(environment["RUNWAY_CLAUDE_SESSION_ID"] == IssueAgentSession.id(
            provider: .claude,
            repository: "VISKA-IO/monorepo",
            issueNumber: 10388
        ).uuidString.lowercased())
        #expect(environment["RUNWAY_GEMINI_SESSION_ID"] == IssueAgentSession.id(
            provider: .gemini,
            repository: "VISKA-IO/monorepo",
            issueNumber: 10388
        ).uuidString.lowercased())
    }

    @Test("Supported autorun commands use the scoped provider adapter")
    func scopedProviderAutorun() {
        let claude = AgentControl.environment(for: UUID(), autorun: "claude --model opus")
        let gemini = AgentControl.environment(for: UUID(), autorun: "gemini --yolo")
        let custom = AgentControl.environment(for: UUID(), autorun: "my-agent --fast")

        #expect(claude["RUNWAY_AUTORUN"]?.contains("Application Support/Runway/bin/claude'") == true)
        #expect(claude["RUNWAY_AUTORUN"]?.hasSuffix(" --model opus") == true)
        #expect(gemini["RUNWAY_AUTORUN"]?.contains("Application Support/Runway/bin/gemini'") == true)
        #expect(gemini["RUNWAY_AUTORUN"]?.hasSuffix(" --yolo") == true)
        #expect(custom["RUNWAY_AUTORUN"] == "my-agent --fast")
    }

    @Test("Ordinary terminals do not expose provider bindings")
    func ordinaryTerminalEnvironment() {
        let environment = AgentControl.environment(for: UUID())

        #expect(environment["RUNWAY_CLAUDE_SESSION_ID"] == nil)
        #expect(environment["RUNWAY_GEMINI_SESSION_ID"] == nil)
    }

    @Test("Focus conversation binding is opt-in")
    func disabledFocusTerminalEnvironment() {
        let environment = AgentControl.environment(
            for: UUID(),
            focusRepository: "VISKA-IO/monorepo",
            focusIssueNumber: 10388
        )

        #expect(environment["RUNWAY_CLAUDE_SESSION_ID"] == nil)
        #expect(environment["RUNWAY_GEMINI_SESSION_ID"] == nil)
    }
}
