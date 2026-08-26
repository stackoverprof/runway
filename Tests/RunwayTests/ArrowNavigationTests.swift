import Testing
@testable import Runway

@Suite("Arrow navigation")
struct ArrowNavigationTests {
    private let left: UInt16 = 123
    private let right: UInt16 = 124
    private let down: UInt16 = 125
    private let up: UInt16 = 126

    private func outcome(
        _ keyCode: UInt16,
        shifted: Bool = false,
        axis: TerminalLayoutAxis,
        quick: Bool = false,
        inQuick: Bool = false,
        atFirstAgent: Bool = false
    ) -> ArrowNavigation.Outcome? {
        ArrowNavigation.outcome(
            keyCode: keyCode,
            shifted: shifted,
            axis: axis,
            quickTerminalVisible: quick,
            quickTerminalFocused: inQuick,
            focusedIsFirstAgent: atFirstAgent
        )
    }

    @Test("Side-by-side agents step with left and right")
    func horizontalUsesHorizontalArrows() {
        #expect(outcome(left, axis: .horizontal) == .focusPrevious)
        #expect(outcome(right, axis: .horizontal) == .focusNext)
    }

    @Test("Stacked agents keep stepping with up and down")
    func verticalUsesVerticalArrows() {
        #expect(outcome(up, axis: .vertical) == .focusPrevious)
        #expect(outcome(down, axis: .vertical) == .focusNext)
    }

    @Test("Every arrow steps between agents when the quick terminal is closed")
    func idleCrossPairAlsoNavigates() {
        #expect(outcome(left, axis: .vertical) == .focusPrevious)
        #expect(outcome(right, axis: .vertical) == .focusNext)
        #expect(outcome(up, axis: .horizontal) == .focusPrevious)
        #expect(outcome(down, axis: .horizontal) == .focusNext)
    }

    @Test("The quick terminal is always left, never up or down")
    func quickTerminalIsReachedLeftward() {
        // Stacked: the agents step with up and down, so left is free from any
        // of them.
        #expect(outcome(left, axis: .vertical, quick: true) == .focusQuickTerminal)
        // Side by side: the quick terminal is the cell left of the first agent,
        // so only that agent crosses over.
        #expect(
            outcome(left, axis: .horizontal, quick: true, atFirstAgent: true)
                == .focusQuickTerminal
        )
        // Vertical arrows never reach it on either axis.
        #expect(outcome(down, axis: .horizontal, quick: true) == .focusNext)
        #expect(outcome(up, axis: .horizontal, quick: true) == .focusPrevious)
        #expect(outcome(down, axis: .vertical, quick: true) == .focusNext)
        #expect(outcome(up, axis: .vertical, quick: true) == .focusPrevious)
    }

    @Test("Right comes back out of the quick terminal, and left stays put")
    func rightReturnsToTheAgents() {
        for axis in [TerminalLayoutAxis.vertical, .horizontal] {
            #expect(outcome(right, axis: axis, quick: true, inQuick: true) == .focusAgents)
            #expect(
                outcome(left, axis: axis, quick: true, inQuick: true)
                    == .focusQuickTerminal
            )
        }
    }

    @Test("Stepping between side-by-side agents survives an open quick terminal")
    func quickTerminalLeavesNavigationAlone() {
        // Anywhere but the first agent, left is still the previous agent.
        #expect(outcome(left, axis: .horizontal, quick: true) == .focusPrevious)
        #expect(outcome(right, axis: .horizontal, quick: true) == .focusNext)
        #expect(outcome(up, axis: .vertical, quick: true) == .focusPrevious)
        // Right only leaves the agents from inside the quick terminal.
        #expect(outcome(right, axis: .vertical, quick: true) == .focusNext)
    }

    @Test("Shift reorders on every arrow, quick terminal or not")
    func shiftAlwaysReorders() {
        #expect(outcome(left, shifted: true, axis: .horizontal) == .reorderPrevious)
        #expect(outcome(right, shifted: true, axis: .horizontal) == .reorderNext)
        #expect(outcome(up, shifted: true, axis: .vertical) == .reorderPrevious)
        #expect(outcome(down, shifted: true, axis: .vertical) == .reorderNext)
        #expect(outcome(down, shifted: true, axis: .horizontal, quick: true) == .reorderNext)
        #expect(outcome(left, shifted: true, axis: .vertical, quick: true) == .reorderPrevious)
    }

    @Test("Anything that is not an arrow is left to the bound shortcuts")
    func ignoresOtherKeys() {
        #expect(outcome(36, axis: .vertical) == nil)
        #expect(outcome(12, axis: .horizontal, quick: true) == nil)
    }
}
