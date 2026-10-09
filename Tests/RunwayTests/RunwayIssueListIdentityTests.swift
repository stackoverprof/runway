import Foundation
import Testing
@testable import Runway

@Suite("Issue list scroll identity")
struct RunwayIssueListIdentityTests {
    private func issue(_ number: Int) -> AssignedIssue {
        AssignedIssue(
            number: number,
            title: "Issue \(number)",
            state: "OPEN",
            closedAt: nil,
            createdAt: nil,
            updatedAt: nil,
            url: URL(string: "https://github.com/owner/repo/issues/\(number)")!
        )
    }

    @Test("A new issue rebuilds the scroll view so a stale offset cannot hide it")
    func membershipChange() {
        let before = RunwayIssueListIdentity(
            repository: "owner/repo", lane: .open,
            issues: [issue(57)], resetGeneration: 0
        )
        let after = RunwayIssueListIdentity(
            repository: "owner/repo", lane: .open,
            issues: [issue(72), issue(57)], resetGeneration: 0
        )

        #expect(before != after)
    }

    @Test("Reordering the same issues preserves the scroll view during drag")
    func reorderKeepsScroll() {
        let before = RunwayIssueListIdentity(
            repository: "owner/repo", lane: .open,
            issues: [issue(72), issue(57)], resetGeneration: 0
        )
        let after = RunwayIssueListIdentity(
            repository: "owner/repo", lane: .open,
            issues: [issue(57), issue(72)], resetGeneration: 0
        )

        #expect(before == after)
    }

    @Test("Reset recreates the scroll view even when issue order was already default")
    func resetRebuildsScroll() {
        let before = RunwayIssueListIdentity(
            repository: "owner/repo", lane: .open,
            issues: [issue(72), issue(57)], resetGeneration: 0
        )
        let after = RunwayIssueListIdentity(
            repository: "owner/repo", lane: .open,
            issues: [issue(72), issue(57)], resetGeneration: 1
        )

        #expect(before != after)
    }
}
