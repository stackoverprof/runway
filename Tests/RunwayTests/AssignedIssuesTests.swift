import Foundation
import Testing
@testable import Runway

@MainActor struct AssignedIssuesTests {
    @Test func fullRefreshFindsUnassignedIssuesWithinOneMinute() {
        let now = Date(timeIntervalSince1970: 10_000)

        #expect(AssignedIssues.needsFullRefresh(
            lastFullFetchedAt: nil, now: now, explicitlyRequested: false
        ))
        #expect(!AssignedIssues.needsFullRefresh(
            lastFullFetchedAt: now.addingTimeInterval(-59),
            now: now, explicitlyRequested: false
        ))
        #expect(AssignedIssues.needsFullRefresh(
            lastFullFetchedAt: now.addingTimeInterval(-60),
            now: now, explicitlyRequested: false
        ))
        #expect(AssignedIssues.needsFullRefresh(
            lastFullFetchedAt: now,
            now: now, explicitlyRequested: true
        ))
    }

    @Test func fullRefreshRemovesIssuesMissingAfterUnassignment() {
        let formerlyAssigned = issue(number: 14395, title: "Formerly assigned")
        let stillAssigned = issue(number: 14373, title: "Still assigned")

        let refreshed = AssignedIssues.issuesAfterRefresh(
            current: [formerlyAssigned, stillAssigned],
            fetched: [stillAssigned],
            fullRefresh: true
        )
        #expect(refreshed.map(\.number) == [14373])

        let incremental = AssignedIssues.issuesAfterRefresh(
            current: [formerlyAssigned, stillAssigned],
            fetched: [stillAssigned],
            fullRefresh: false
        )
        #expect(Set(incremental.map(\.number)) == [14395, 14373])
    }

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

    @Test func staleRefreshKeepsOptimisticRenameUntilGitHubConfirmsIt() {
        let stale = issue(number: 10675, title: "Old title")
        let preserved = AssignedIssues.preservingOptimisticTitles(
            in: [stale],
            pending: [10675: "New title"]
        )

        #expect(preserved.issues.first?.title == "New title")
        #expect(preserved.confirmed.isEmpty)

        let confirmed = AssignedIssues.preservingOptimisticTitles(
            in: [issue(number: 10675, title: "New title")],
            pending: [10675: "New title"]
        )
        #expect(confirmed.issues.first?.title == "New title")
        #expect(confirmed.confirmed == [10675])
    }

    @Test func issueSearchMatchesTitleAndNumberInAnyOrder() {
        let target = issue(number: 11221, title: "Cli: Menu catalog + metadata")

        #expect(
            AssignedIssue.matchesSearchQuery(
                "Cli: Menu catalog + metadata #11221",
                issue: target,
                repositoryName: "monorepo"
            )
        )
        #expect(
            AssignedIssue.matchesSearchQuery(
                "#11221 Cli: Menu catalog",
                issue: target,
                repositoryName: "monorepo"
            )
        )
    }

    @Test func issueSearchIgnoresAccents() {
        let target = issue(number: 11300, title: "Cust: KSÍ smoke")

        #expect(
            AssignedIssue.matchesSearchQuery(
                "ksi smoke",
                issue: target,
                repositoryName: "monorepo"
            )
        )
    }

    private func issue(number: Int, title: String) -> AssignedIssue {
        AssignedIssue(
            number: number,
            title: title,
            state: "OPEN",
            closedAt: nil,
            createdAt: nil,
            updatedAt: nil,
            url: URL(string: "https://github.com/owner/repository/issues/\(number)")!
        )
    }
}
