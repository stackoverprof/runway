import Testing
@testable import Runway

@MainActor struct AssignedIssuesTests {
    @Test func returningToBacklogWithoutTargetRestoresSavedPosition() {
        let order = [10675, 10674, 10597]

        let returned = AssignedIssues.returnedBacklogOrder(
            order,
            issueNumber: 10675,
            before: nil
        )

        #expect(returned == order)
    }

    @Test func returningToBacklogCanMoveBeforeExplicitTarget() {
        let returned = AssignedIssues.returnedBacklogOrder(
            [10675, 10674, 10597],
            issueNumber: 10675,
            before: 10597
        )

        #expect(returned == [10674, 10675, 10597])
    }

    @Test func returningIssueMissingFromBacklogDefaultsToTop() {
        let returned = AssignedIssues.returnedBacklogOrder(
            [10674, 10597],
            issueNumber: 10675,
            before: nil
        )

        #expect(returned == [10675, 10674, 10597])
    }

    @Test func closingIssueMovesItToTopOfClosedBacklog() {
        let orders = AssignedIssues.ordersAfterStateChange(
            open: [10675, 10674],
            closed: [10437],
            issueNumber: 10675,
            closed: true
        )

        #expect(orders.open == [10674])
        #expect(orders.closed == [10675, 10437])
    }

    @Test func reopeningIssueMovesItToTopOfOpenBacklog() {
        let orders = AssignedIssues.ordersAfterStateChange(
            open: [10674],
            closed: [10675, 10437],
            issueNumber: 10675,
            closed: false
        )

        #expect(orders.open == [10675, 10674])
        #expect(orders.closed == [10437])
    }
}
