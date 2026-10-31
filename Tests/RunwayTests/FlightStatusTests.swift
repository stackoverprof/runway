import Testing

@testable import Runway

@Suite("Where a flight is")
struct FlightStatusTests {
    private func steps(_ body: String) -> [IssueBody.Step] {
        IssueBody.steps("Progress", in: "## Progress\n" + body)
    }

    @Test("A closed issue has landed")
    func landed() {
        #expect(FlightStatus.of(closed: true, steps: steps("- [ ] Anything")) == .landed)
    }

    @Test("Nothing ticked and nothing waiting is still on the stand")
    func onTheStand() {
        let body = """
        - [ ] Merge #16797
        - [ ] Sentry 11 upgrade
        - [ ] /close
        """
        #expect(FlightStatus.of(closed: false, steps: steps(body)) == .onTheStand)
    }

    @Test("A step that says what it waits on puts the flight in a hold")
    func holding() {
        let body = """
        - [x] Merge #16797
        - [ ] Sentry 11 upgrade (needs: your yes to start)
        - [ ] Stripe 23 upgrade
        - [ ] /close
        """
        #expect(FlightStatus.of(closed: false, steps: steps(body)) == .holding)
    }

    @Test("Work done and more to do is en route")
    func enRoute() {
        let body = """
        - [x] Merge #16797
        - [ ] Sentry 11 upgrade
        - [ ] Stripe 23 upgrade
        - [ ] /close
        """
        #expect(FlightStatus.of(closed: false, steps: steps(body)) == .enRoute)
    }

    @Test("One step left, or none, is on approach")
    func onApproach() {
        let nearly = """
        - [x] Merge #16797
        - [ ] Sentry 11 upgrade
        - [ ] /close
        """
        let allDone = """
        - [x] Merge #16797
        - [x] Sentry 11 upgrade
        - [ ] /close
        """
        #expect(FlightStatus.of(closed: false, steps: steps(nearly)) == .onApproach)
        #expect(FlightStatus.of(closed: false, steps: steps(allDone)) == .onApproach)
    }

    @Test("A flight with no checklist has not left the stand")
    func noChecklist() {
        #expect(FlightStatus.of(closed: false, steps: []) == .onTheStand)
    }
}
