import Foundation
import Testing

@testable import Runway

@Suite("Seat bindings")
@MainActor
struct SeatBindingTests {
    @Test("A pilot and its copilot never share one conversation")
    func pilotAndCopilotDiffer() {
        let pilot = AgentControl.issueProviderSessionFile(
            repository: "VISKA-IO/monorepo", issueNumber: 17345, rank: .pilot
        )
        let copilot = AgentControl.issueProviderSessionFile(
            repository: "VISKA-IO/monorepo", issueNumber: 17345, rank: .copilot
        )
        #expect(pilot != copilot)
    }

    @Test("A crew keeps the binding its issue already had")
    func crewKeepsItsBinding() {
        let crew = AgentControl.issueProviderSessionFile(
            repository: "VISKA-IO/monorepo", issueNumber: 16790, rank: .crew
        )
        let unranked = AgentControl.issueProviderSessionFile(
            repository: "VISKA-IO/monorepo", issueNumber: 16790
        )
        #expect(crew == unranked)
    }
}
