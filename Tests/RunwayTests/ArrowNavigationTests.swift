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
        quick: Bool = false
    ) -> ArrowNavigation.Outcome? {
        ArrowNavigation.outcome(
            keyCode: keyCode,
            shifted: shifted,
            axis: axis,
            quickTerminalVisible: quick
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

    @Test("The other pair still steps between agents when nothing is across the pane")
    func idleCrossPairAlsoNavigates() {
        #expect(outcome(left, axis: .vertical) == .focusPrevious)
        #expect(outcome(right, axis: .vertical) == .focusNext)
        #expect(outcome(up, axis: .horizontal) == .focusPrevious)
        #expect(outcome(down, axis: .horizontal) == .focusNext)
    }

    @Test("An open quick terminal claims the pair that points at it")
    func quickTerminalClaimsCrossPair() {
        #expect(outcome(left, axis: .vertical, quick: true) == .focusQuickTerminal)
        #expect(outcome(right, axis: .vertical, quick: true) == .focusAgents)
        #expect(outcome(down, axis: .horizontal, quick: true) == .focusQuickTerminal)
        #expect(outcome(up, axis: .horizontal, quick: true) == .focusAgents)
    }

    @Test("Stepping between agents survives an open quick terminal")
    func quickTerminalLeavesNavigationAlone() {
        #expect(outcome(left, axis: .horizontal, quick: true) == .focusPrevious)
        #expect(outcome(right, axis: .horizontal, quick: true) == .focusNext)
        #expect(outcome(up, axis: .vertical, quick: true) == .focusPrevious)
        #expect(outcome(down, axis: .vertical, quick: true) == .focusNext)
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
