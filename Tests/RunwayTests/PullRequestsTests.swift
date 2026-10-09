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

    @Test("Pull request display order separates drafts and uses lifecycle dates")
    func displayOrderUsesLifecycleDates() {
        let oldOpen = makePullRequest(
            number: 1,
            state: "OPEN",
            createdAt: start.addingTimeInterval(-300),
            updatedAt: start.addingTimeInterval(300)
        )
        let newerOpen = makePullRequest(
            number: 2,
            state: "OPEN",
            createdAt: start.addingTimeInterval(-60),
            updatedAt: start.addingTimeInterval(-300)
        )
        let draft = makePullRequest(
            number: 3,
            state: "OPEN",
            createdAt: start.addingTimeInterval(-30),
            updatedAt: start.addingTimeInterval(600),
            isDraft: true
        )
        let mergedEarlier = makePullRequest(
            number: 4,
            state: "MERGED",
            createdAt: start.addingTimeInterval(-900),
            updatedAt: start.addingTimeInterval(900),
            mergedAt: start.addingTimeInterval(-120)
        )
        let mergedLater = makePullRequest(
            number: 5,
            state: "MERGED",
            createdAt: start.addingTimeInterval(-1_200),
            updatedAt: start.addingTimeInterval(-30),
            mergedAt: start.addingTimeInterval(-30)
        )

        let ordered = [mergedEarlier, draft, mergedLater, oldOpen, newerOpen]
            .sorted(by: RepositoryPullRequest.displaySort)
        #expect(ordered.map(\.number) == [3, 2, 1, 5, 4])
    }

    @Test("Drafts have their own developer count")
    func draftCountIsSeparateFromOpen() {
        let developer = PullRequestDeveloper(
            login: "developer",
            name: "Developer",
            pullRequests: [
                makePullRequest(
                    number: 1,
                    state: "OPEN",
                    createdAt: start,
                    updatedAt: start
                ),
                makePullRequest(
                    number: 2,
                    state: "OPEN",
                    createdAt: start,
                    updatedAt: start,
                    isDraft: true
                ),
            ]
        )

        #expect(developer.openCount == 1)
        #expect(developer.draftCount == 1)
        #expect(developer.closedCount == 0)
    }

    @Test("One open PR ranks above one draft PR")
    func openOutranksDraft() {
        let draft = PullRequestDeveloper(
            login: "fahri", name: "Fahri",
            pullRequests: [makePullRequest(
                state: "OPEN", createdAt: start, updatedAt: start, isDraft: true
            )]
        )
        let open = PullRequestDeveloper(
            login: "zul", name: "Zul",
            pullRequests: [makePullRequest(
                state: "OPEN", createdAt: start, updatedAt: start
            )]
        )

        #expect([draft, open].sorted { PullRequestDeveloper.ranksAbove($0, $1) }
            .map(\.login) == ["zul", "fahri"])
    }

    @Test("Two drafts tie one open PR, with the open PR winning the tie")
    func openWinsWeightedTie() {
        let drafts = PullRequestDeveloper(
            login: "drafts", name: "Drafts",
            pullRequests: [1, 2].map { number in
                makePullRequest(
                    number: number, state: "OPEN", createdAt: start,
                    updatedAt: start, isDraft: true
                )
            }
        )
        let open = PullRequestDeveloper(
            login: "open", name: "Open",
            pullRequests: [makePullRequest(
                state: "OPEN", createdAt: start, updatedAt: start
            )]
        )

        #expect(PullRequestDeveloper.ranksAbove(open, drafts))
    }

    private func makePullRequest(
        number: Int = 1234,
        state: String,
        createdAt: Date,
        updatedAt: Date,
        mergedAt: Date? = nil,
        closedAt: Date? = nil,
        isDraft: Bool = false
    ) -> RepositoryPullRequest {
        RepositoryPullRequest(
            number: number,
            title: "Test pull request",
            state: state,
            isDraft: isDraft,
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
