import Testing

@testable import Runway

@Suite("A step carries its own blocker")
struct StepBlockerTests {
    private let body = """
    ## Progress
    - [x] Merge #16797
    - [ ] Sentry 11 upgrade (needs: your yes to start)
    - [ ] Clear the 1-major tail
    """

    @Test("The blocker is read off the step and kept out of its label")
    func readsTheBlocker() {
        let steps = IssueBody.steps("Progress", in: body)
        #expect(steps.count == 3)
        #expect(steps[1].label == "Sentry 11 upgrade")
        #expect(steps[1].needs == "your yes to start")
    }

    @Test("A step with nothing waiting on it reads plainly")
    func plainStep() {
        let steps = IssueBody.steps("Progress", in: body)
        #expect(steps[2].needs == nil)
        #expect(steps[2].label == "Clear the 1-major tail")
        #expect(steps[0].done)
    }
}
