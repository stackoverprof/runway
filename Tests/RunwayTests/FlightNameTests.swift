import Foundation
import Testing
@testable import Runway

@Suite("What a flight is called")
@MainActor
struct FlightNameTests {
    @Test("A pilot takes the name before the colon")
    func clusterName() {
        #expect(FlightCrewSessions.flightName("Dependency: Keep the stack current") == "dependency")
        #expect(FlightCrewSessions.flightName("Teya Ecom: rollout closure") == "teya-ecom")
    }

    @Test("A title with no colon is the name, and punctuation folds to one dash")
    func wholeTitle() {
        #expect(FlightCrewSessions.flightName("Saffran") == "saffran")
        #expect(FlightCrewSessions.flightName("Brauð & Co: plan") == "brauð-co")
        #expect(FlightCrewSessions.flightName("  ") == nil)
    }

    @Test("A pilot reads as its flight; a crew reads as its issue")
    func sessionNames() {
        let title = "Dependency: Keep the stack current"
        #expect(FlightCrewSessions.sessionName(
            rank: .pilot, repository: "VISKA-IO/monorepo", issue: 17345, title: title
        ) == "dependency")
        #expect(FlightCrewSessions.sessionName(
            rank: .copilot, repository: "VISKA-IO/monorepo", issue: 17345, title: title
        ) == "dependency-copilot")
        #expect(FlightCrewSessions.sessionName(
            rank: .crew, repository: "VISKA-IO/monorepo", issue: 16790, title: "whatever"
        ) == "monorepo-16790")
    }
}
