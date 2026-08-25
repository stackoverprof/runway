import Foundation
import Testing
@testable import Runway

@Suite("Quick terminal conversation")
struct QuickTerminalSessionTests {
    /// A throwaway domain per test, so a stored root never leaks between them.
    private func store(_ name: String) -> UserDefaults {
        let suite = "runway.tests.quickSession.\(name)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    @Test("The kept conversation survives reads, which is what survives a relaunch")
    func rootIsMintedOnceAndKept() {
        let defaults = store("kept")
        let first = QuickTerminalSession.root(in: defaults)
        #expect(!first.isEmpty)
        #expect(QuickTerminalSession.root(in: defaults) == first)
        #expect(
            QuickTerminalSession.id(provider: .claude, in: defaults)
                == QuickTerminalSession.id(provider: .claude, in: defaults)
        )
    }

    @Test("Only a deliberate new session changes the id")
    func rotateChangesTheID() {
        let defaults = store("rotate")
        let before = QuickTerminalSession.id(provider: .claude, in: defaults)
        QuickTerminalSession.rotate(in: defaults)
        let after = QuickTerminalSession.id(provider: .claude, in: defaults)
        #expect(before != after)
        #expect(QuickTerminalSession.id(provider: .claude, in: defaults) == after)
    }

    @Test("Quick, Focus, and each provider stay in their own namespace")
    func distinctNamespaces() {
        let root = "0a4f8f1e-1111-4222-8333-444455556666"
        let quick = QuickTerminalSession.id(provider: .claude, root: root)
        let gemini = QuickTerminalSession.id(provider: .gemini, root: root)
        let issue = IssueAgentSession.id(
            provider: .claude,
            repository: "owner/repo",
            issueNumber: 1
        )
        #expect(quick != gemini)
        #expect(quick != issue)
    }

    @Test("Ids are valid v4 UUIDs for the provider CLIs")
    func uuidShape() {
        let text = QuickTerminalSession
            .id(provider: .claude, root: "seed")
            .uuidString
        #expect(text[text.index(text.startIndex, offsetBy: 14)] == "4")
        #expect("89AB".contains(text[text.index(text.startIndex, offsetBy: 19)]))
    }

    @Test("The quick terminal's shell is bound and runs Runway's own wrapper")
    func quickEnvironmentBindsThroughTheWrapper() {
        let env = AgentControl.environment(
            for: QuickTerminal.quickBoxID,
            autorun: "claude",
            quickTerminalSession: true
        )
        #expect(env["RUNWAY_CLAUDE_SESSION_ID"] != nil)
        #expect(env["RUNWAY_GEMINI_SESSION_ID"] != nil)
        #expect(env["RUNWAY_SESSION_FILE"] != nil)
        // The wrapper must be reached by absolute path: the user's own zsh
        // config can prepend a directory holding the real claude.
        #expect(env["RUNWAY_AUTORUN"] != "claude")
        #expect(
            env["RUNWAY_AUTORUN"]?
                .contains(AgentControl.binDir.appendingPathComponent("claude").path) == true
        )
    }

    @Test("A Focus box without the experiment stays unbound")
    func focusBindingIsStillOptIn() {
        let env = AgentControl.environment(
            for: UUID(),
            autorun: "claude",
            focusRepository: "owner/repo",
            focusIssueNumber: 7,
            issueAgentSessionsEnabled: false
        )
        #expect(env["RUNWAY_CLAUDE_SESSION_ID"] == nil)
    }
}
