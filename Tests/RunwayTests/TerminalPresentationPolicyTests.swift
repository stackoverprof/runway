import Testing
@testable import Runway

@Suite("Terminal presentation policy")
struct TerminalPresentationPolicyTests {
    @Test("Solo navigation keeps active repository terminals in accordion flow")
    func soloAccordionFlow() {
        #expect(TerminalPresentationPolicy.state(
            isActiveRepository: true,
            isSoloed: true,
            isFocused: false
        ) == TerminalPresentationState(isInLayout: true, isInteractive: false))

        #expect(TerminalPresentationPolicy.state(
            isActiveRepository: true,
            isSoloed: true,
            isFocused: true
        ) == TerminalPresentationState(isInLayout: true, isInteractive: true))
    }

    @Test("Other repositories stay parked outside the layout")
    func inactiveRepositoryParking() {
        #expect(TerminalPresentationPolicy.state(
            isActiveRepository: false,
            isSoloed: false,
            isFocused: false
        ) == TerminalPresentationState(isInLayout: false, isInteractive: false))
    }
}
