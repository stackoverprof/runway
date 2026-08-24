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

    @Test("A half-written session file resolves to nothing rather than a bad command")
    func rejectsIncompleteRecord() {
        #expect(AgentSessionLocator.recorded(in: "") == nil)
        #expect(AgentSessionLocator.recorded(in: #"{"provider":"claude"}"#) == nil)
        #expect(AgentSessionLocator.recorded(in: #"{"sessionId":"  "}"#) == nil)
    }
}
