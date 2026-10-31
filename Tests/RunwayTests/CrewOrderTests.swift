import Foundation
import Testing

@testable import Runway

@Suite("Crews fly in the checklist's order")
struct CrewOrderTests {
    private func crew(_ number: Int, _ title: String, closed: Bool = false) -> IssueLeg {
        IssueLeg(
            number: number,
            title: title,
            state: closed ? "CLOSED" : "OPEN",
            url: URL(string: "https://github.com/x/y/issues/\(number)")!,
            repository: nil
        )
    }

    private let steps = IssueBody.steps("Progress", in: """
    ## Progress
    - [ ] Merge #16797
    - [ ] Sentry 11 upgrade (needs: your yes to start)
    - [ ] Stripe 23 upgrade
    - [ ] Vercel sites to React Router 8
    - [ ] Clear the 1-major tail
    - [ ] /close
    """)

    @Test("A crew sits where its step sits, by title")
    func byTitle() {
        let crews = [
            crew(10757, "Dependency: Clear 1-major tail"),
            crew(16792, "Dependency: Stripe 23 upgrade"),
            crew(16791, "Dependency: Sentry 11 upgrade"),
        ]
        #expect(CrewOrder.sorted(crews, by: steps).map(\.number) == [16791, 16792, 10757])
    }

    @Test("A step naming the issue number wins")
    func byNumber() {
        let crews = [crew(99, "Something else"), crew(16797, "Dependency: 7 small safe updates")]
        #expect(CrewOrder.sorted(crews, by: steps).map(\.number) == [16797, 99])
    }

    @Test("A crew no step mentions keeps its place at the back")
    func unmentioned() {
        let crews = [
            crew(500, "Dependency: Something nobody listed"),
            crew(16791, "Dependency: Sentry 11 upgrade"),
        ]
        #expect(CrewOrder.sorted(crews, by: steps).map(\.number) == [16791, 500])
    }

    @Test("Landed crews go to the bottom whatever their step")
    func landedLast() {
        let crews = [
            crew(16792, "Dependency: Stripe 23 upgrade"),
            crew(16791, "Dependency: Sentry 11 upgrade", closed: true),
        ]
        #expect(CrewOrder.sorted(crews, by: steps).map(\.number) == [16792, 16791])
    }

    @Test("With no checklist the order is left alone")
    func noChecklist() {
        let crews = [crew(3, "C"), crew(1, "A"), crew(2, "B")]
        #expect(CrewOrder.sorted(crews, by: []).map(\.number) == [3, 1, 2])
    }
}
