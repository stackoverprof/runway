import Foundation
import Testing

@testable import Runway

@Suite("The board's own arrangement")
@MainActor
struct FlightBoardTests {
    private func flight(_ number: Int) -> AssignedIssue {
        AssignedIssue(
            number: number,
            title: "Flight \(number)",
            state: "OPEN",
            closedAt: nil,
            createdAt: nil,
            updatedAt: nil,
            url: URL(string: "https://github.com/x/y/issues/\(number)")!
        )
    }

    @Test("An unplaced flight sits at the top, newest first")
    func unplacedComeFirst() {
        let repo = "test/board-unplaced"
        FlightBoard.shared.setOrder([], in: repo)
        let ordered = FlightBoard.shared.ordered([flight(1), flight(3), flight(2)], in: repo)
        #expect(ordered.map(\.number) == [3, 2, 1])
    }

    @Test("A saved order is kept, and a new flight joins at the top")
    func savedOrderKept() {
        let repo = "test/board-saved"
        FlightBoard.shared.setOrder([2, 1, 3], in: repo)
        let ordered = FlightBoard.shared.ordered(
            [flight(1), flight(2), flight(3), flight(9)],
            in: repo
        )
        #expect(ordered.map(\.number) == [9, 2, 1, 3])
    }

    @Test("A priority is remembered, and cleared when set to none")
    func priority() {
        let repo = "test/board-priority"
        FlightBoard.shared.setPriority(2, for: 42, in: repo)
        #expect(FlightBoard.shared.priority(42, in: repo) == 2)
        FlightBoard.shared.setPriority(nil, for: 42, in: repo)
        #expect(FlightBoard.shared.priority(42, in: repo) == nil)
    }
}
