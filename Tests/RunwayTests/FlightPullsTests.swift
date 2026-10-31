import Testing

@testable import Runway

@Suite("Pull requests an issue points at")
@MainActor
struct FlightPullsTests {
    @Test("Every number in the body is found")
    func findsNumbers() {
        let body = """
        ## Acceptance
        - [ ] #17340 reviewed and merged.
        - [ ] #17338 reviewed and merged, with #17337 on main first.
        """
        #expect(MiddlePane.referenced(in: body) == [17340, 17338, 17337])
    }

    @Test("A number at the very end is not dropped")
    func trailingNumber() {
        #expect(MiddlePane.referenced(in: "see #42") == [42])
    }

    @Test("Text with no references finds nothing")
    func nothingToFind() {
        #expect(MiddlePane.referenced(in: "Nothing here, and a stray # too").isEmpty)
    }
}
