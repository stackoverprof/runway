import Foundation
import Testing
@testable import Runway

@Suite("Accordion span policy")
struct AccordionSpanPolicyTests {
    @Test("Focused box gets twice the others' share, and shares fill the pane")
    func weightedSplit() {
        let focused = AccordionSpanPolicy.span(
            isFocused: true, focusedIsActive: true, soloed: false,
            paneSpan: 1000, count: 3, minimumSpan: 50
        )
        let other = AccordionSpanPolicy.span(
            isFocused: false, focusedIsActive: true, soloed: false,
            paneSpan: 1000, count: 3, minimumSpan: 50
        )
        #expect(focused == other * 2)
        #expect(abs(focused + other * 2 - (1000 - 32 - 24)) < 0.001)
    }

    @Test("No focus means an equal split")
    func equalSplit() {
        let span = AccordionSpanPolicy.span(
            isFocused: false, focusedIsActive: false, soloed: false,
            paneSpan: 1000, count: 4, minimumSpan: 50
        )
        #expect(abs(span - (1000 - 32 - 36) / 4) < 0.001)
    }

    @Test("Solo hands the whole pane to the focused box")
    func solo() {
        #expect(AccordionSpanPolicy.span(
            isFocused: true, focusedIsActive: true, soloed: true,
            paneSpan: 800, count: 5, minimumSpan: 50
        ) == 768)
        #expect(AccordionSpanPolicy.span(
            isFocused: false, focusedIsActive: true, soloed: true,
            paneSpan: 800, count: 5, minimumSpan: 50
        ) == 0)
    }

    @Test("A crowded narrow pane never squeezes below the minimum")
    func minimumFloor() {
        let span = AccordionSpanPolicy.span(
            isFocused: false, focusedIsActive: false, soloed: false,
            paneSpan: 300, count: 6, minimumSpan: 120
        )
        #expect(span == 120)
    }

    @Test("The same numbers drive both axes")
    func axisAgnostic() {
        let vertical = AccordionSpanPolicy.span(
            isFocused: true, focusedIsActive: true, soloed: false,
            paneSpan: 900, count: 2, minimumSpan: 50
        )
        let horizontal = AccordionSpanPolicy.span(
            isFocused: true, focusedIsActive: true, soloed: false,
            paneSpan: 900, count: 2, minimumSpan: 120
        )
        #expect(vertical == horizontal)
    }
}
