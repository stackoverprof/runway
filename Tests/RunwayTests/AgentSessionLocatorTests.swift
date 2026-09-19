import Foundation
import Testing
@testable import Runway

@Suite("Agent session locator")
struct AgentSessionLocatorTests {
    @Test("A project directory matches the path it was named after")
    func projectKeyMatchesPath() {
        #expect(
            AgentSessionLocator.normalizedProjectKey("/Users/erbin/Developer/runway")
                == AgentSessionLocator.normalizedProjectKey("-Users-erbin-Developer-runway")
        )
    }

    @Test("Dots and repeated separators do not break the match")
    func toleratesSubstitutionDifferences() {
        #expect(
            AgentSessionLocator.normalizedProjectKey("/Users/erbin/dev/upsell.is")
                == AgentSessionLocator.normalizedProjectKey("-Users-erbin-dev-upsell-is")
        )
        #expect(
            AgentSessionLocator.normalizedProjectKey("/Users/erbin//dev/")
                == AgentSessionLocator.normalizedProjectKey("Users-erbin-dev")
        )
    }

    @Test("Different projects never collide")
    func distinctProjects() {
        #expect(
            AgentSessionLocator.normalizedProjectKey("/repos/upsell-hr")
                != AgentSessionLocator.normalizedProjectKey("/repos/monorepo")
        )
    }

    @Test("A recorded session becomes a runnable resume command")
    func recordedSession() {
        let resolved = AgentSessionLocator.recorded(
            in: #"{"provider":"claude","sessionId":"0b6f2b1e-1f0b-4a7e-9d21-6a5a2c1b7f30"}"#
        )
        #expect(resolved?.provider == .claude)
        #expect(
            resolved?.resumeCommand
                == "claude --resume 0b6f2b1e-1f0b-4a7e-9d21-6a5a2c1b7f30"
        )
    }

    @Test("Codex uses its resume subcommand")
    func codexResumeCommand() {
        let resolved = AgentSessionLocator.recorded(
            in: #"{"provider":"codex","sessionId":"019cc6e1-e5ab-7e82-8d57-5112543ef208"}"#
        )
        #expect(
            resolved?.resumeCommand
                == "codex resume 019cc6e1-e5ab-7e82-8d57-5112543ef208"
        )
    }

    @Test("A half-written session file resolves to nothing rather than a bad command")
    func rejectsIncompleteRecord() {
        #expect(AgentSessionLocator.recorded(in: "") == nil)
        #expect(AgentSessionLocator.recorded(in: #"{"provider":"claude"}"#) == nil)
        #expect(AgentSessionLocator.recorded(in: #"{"sessionId":"  "}"#) == nil)
    }

    @Test("A registry entry for this conversation yields the name peers address")
    func peerNameForMatchingSession() {
        let entry = #"""
        {"pid":51644,"sessionId":"c1e65d47-9829-4a11-91a9-abb35f566ec2",
         "name":"monorepo-77","nameSource":"derived","updatedAt":1789801543542}
        """#
        let resolved = AgentSessionLocator.peerName(
            in: entry,
            matching: "c1e65d47-9829-4a11-91a9-abb35f566ec2"
        )
        #expect(resolved?.name == "monorepo-77")
        #expect(resolved?.updatedAt == 1_789_801_543_542)
    }

    @Test("A registry entry for a different conversation is not borrowed")
    func peerNameIgnoresOtherSessions() {
        let entry = #"{"sessionId":"aaaaaaaa-0000-0000-0000-000000000000","name":"runway-b0"}"#
        #expect(AgentSessionLocator.peerName(in: entry, matching: "bbbbbbbb-0000-0000-0000-000000000000") == nil)
    }

    @Test("An entry with no usable name resolves to nothing rather than an empty copy")
    func peerNameRejectsBlankName() {
        let id = "c1e65d47-9829-4a11-91a9-abb35f566ec2"
        #expect(AgentSessionLocator.peerName(in: "", matching: id) == nil)
        #expect(AgentSessionLocator.peerName(in: #"{"sessionId":"\#(id)"}"#, matching: id) == nil)
        #expect(AgentSessionLocator.peerName(in: #"{"sessionId":"\#(id)","name":"  "}"#, matching: id) == nil)
    }
}
