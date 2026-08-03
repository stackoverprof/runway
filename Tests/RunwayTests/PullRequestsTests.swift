import Foundation
import Testing
@testable import Runway

@Suite("Pull request timeframes")
struct PullRequestsTests {
    private let start = Date(timeIntervalSince1970: 2_000_000)

    @Test("Merged PRs use merge time instead of creation time")
    func mergedPRUsesMergeTime() {
        let pullRequest = makePullRequest(
            state: "MERGED",
            createdAt: start.addingTimeInterval(-86_400),
            updatedAt: start.addingTimeInterval(120),
            mergedAt: start.addingTimeInterval(60),
            closedAt: start.addingTimeInterval(60)
        )

        #expect(pullRequest.timeframeDate >= start)
        #expect(pullRequest.timeframeDate == pullRequest.mergedAt)
    }

    @Test("Open PRs use creation time")
    func openPRUsesCreationTime() {
        let pullRequest = makePullRequest(
            state: "OPEN",
            createdAt: start.addingTimeInterval(-86_400),
            updatedAt: start.addingTimeInterval(60)
        )

        #expect(pullRequest.timeframeDate < start)
        #expect(pullRequest.timeframeDate == pullRequest.createdAt)
    }

    @Test("Closed PRs use close time")
    func closedPRUsesCloseTime() {
        let pullRequest = makePullRequest(
            state: "CLOSED",
            createdAt: start.addingTimeInterval(-86_400),
            updatedAt: start.addingTimeInterval(120),
            closedAt: start.addingTimeInterval(60)
        )

        #expect(pullRequest.timeframeDate >= start)
        #expect(pullRequest.timeframeDate == pullRequest.closedAt)
    }

    private func makePullRequest(
        state: String,
        createdAt: Date,
        updatedAt: Date,
        mergedAt: Date? = nil,
        closedAt: Date? = nil
    ) -> RepositoryPullRequest {
        RepositoryPullRequest(
            number: 1234,
            title: "Test pull request",
            state: state,
            isDraft: false,
            author: .init(login: "developer", name: "Developer", isBot: false),
            createdAt: createdAt,
            updatedAt: updatedAt,
            mergedAt: mergedAt,
            closedAt: closedAt,
            url: URL(string: "https://github.com/example/repo/pull/1234")!,
            headRefName: "feature",
            baseRefName: "main"
        )
    }
}
