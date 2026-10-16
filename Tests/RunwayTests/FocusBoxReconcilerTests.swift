import Foundation
import Testing
@testable import Runway

@Suite("Focus terminal reconciliation")
struct FocusBoxReconcilerTests {
    @Test("Renaming a focused issue preserves its terminal session")
    func refreshesTitleWithoutReplacingBox() {
        let existing = AgentBox(
            name: "Old issue title",
            focusRepository: "owner/repository",
            focusIssueNumber: 123
        )

        let result = FocusBoxReconciler.reconcile(
            previousBoxes: [existing],
            issues: [issue(number: 123, title: "Renamed issue title")],
            repository: "owner/repository",
            workingDirectory: "/repos/repository",
            command: "claude",
            retainUnmanagedBoxes: true
        )

        #expect(result.repositoryBoxes.first?.id == existing.id)
        #expect(result.repositoryBoxes.first?.name == "Renamed issue title")
        #expect(result.removedBoxes.isEmpty)
    }

    @Test("An issue whose conversation moved folders reopens in that folder")
    func reopensInRecordedFolder() {
        let result = FocusBoxReconciler.reconcile(
            previousBoxes: [],
            issues: [issue(number: 7, title: "Moved"), issue(number: 8, title: "Stayed")],
            repository: "owner/repository",
            workingDirectory: "/repos/repository",
            workingDirectoriesByIssue: [7: "/repos"],
            command: "claude",
            retainUnmanagedBoxes: true
        )

        #expect(result.repositoryBoxes.map(\.cwd) == ["/repos", "/repos/repository"])
    }

    @Test("Switching repositories retains other repository terminals")
    func retainsOtherRepositoryBoxes() {
        let repositoryABox = AgentBox(
            name: "Issue A",
            focusRepository: "owner/repository-a",
            focusIssueNumber: 101
        )
        let repositoryBBox = AgentBox(
            name: "Old title",
            focusRepository: "owner/repository-b",
            focusIssueNumber: 202
        )

        let result = FocusBoxReconciler.reconcile(
            previousBoxes: [repositoryABox, repositoryBBox],
            issues: [issue(number: 202, title: "New title")],
            repository: "owner/repository-b",
            workingDirectory: "/repos/repository-b",
            command: "claude",
            retainUnmanagedBoxes: true
        )

        #expect(result.boxes.map(\.id) == [repositoryABox.id, repositoryBBox.id])
        #expect(result.repositoryBoxes.first?.name == "New title")
        #expect(result.repositoryBoxes.first?.cwd == "/repos/repository-b")
        #expect(result.removedBoxes.isEmpty)
    }

    @Test("Switching Focus pages keeps both pages' terminal identities alive")
    func keepsParkedFocusPageTerminals() {
        let first = AgentBox(
            name: "Board one",
            focusRepository: "owner/repository",
            focusIssueNumber: 101
        )
        let second = AgentBox(
            name: "Board two",
            focusRepository: "owner/repository",
            focusIssueNumber: 202
        )

        let result = FocusBoxReconciler.reconcile(
            previousBoxes: [first, second],
            issues: [issue(number: 101, title: "Board one"), issue(number: 202, title: "Board two")],
            repository: "owner/repository",
            workingDirectory: "/repos/repository",
            command: "claude",
            retainUnmanagedBoxes: true
        )

        #expect(result.repositoryBoxes.map(\.id) == [first.id, second.id])
        #expect(result.removedBoxes.isEmpty)
    }

    @Test("Removing focus only closes terminals from that repository")
    func removesOnlyCurrentRepositoryBoxes() {
        let repositoryABox = AgentBox(
            name: "Issue A",
            focusRepository: "owner/repository-a",
            focusIssueNumber: 101
        )
        let repositoryBBox = AgentBox(
            name: "Issue B",
            focusRepository: "owner/repository-b",
            focusIssueNumber: 202
        )

        let result = FocusBoxReconciler.reconcile(
            previousBoxes: [repositoryABox, repositoryBBox],
            issues: [],
            repository: "owner/repository-b",
            workingDirectory: "/repos/repository-b",
            command: "claude",
            retainUnmanagedBoxes: true
        )

        #expect(result.boxes.map(\.id) == [repositoryABox.id])
        #expect(result.removedBoxes.map(\.id) == [repositoryBBox.id])
    }

    @Test("A second clone keeps its own board of terminals")
    func secondCloneKeepsOwnBoard() {
        let mainBox = AgentBox(
            name: "Main board",
            focusRepository: "owner/repository",
            focusIssueNumber: 101
        )

        let result = FocusBoxReconciler.reconcile(
            previousBoxes: [mainBox],
            issues: [issue(number: 101, title: "Same issue, other clone")],
            repository: "owner/repository",
            checkout: "/repos/copy",
            workingDirectory: "/repos/copy",
            command: "claude",
            retainUnmanagedBoxes: true
        )

        // The main clone's box is parked, not reused: the copy gets its own.
        #expect(result.boxes.first?.id == mainBox.id)
        #expect(result.boxes.first?.name == "Main board")
        #expect(result.repositoryBoxes.count == 1)
        #expect(result.repositoryBoxes.first?.id != mainBox.id)
        #expect(result.repositoryBoxes.first?.focusCheckout == "/repos/copy")
        #expect(result.repositoryBoxes.first?.cwd == "/repos/copy")
        #expect(result.removedBoxes.isEmpty)
    }

    @Test("A returning issue launches its last-used provider")
    func restoresIssueProvider() {
        let result = FocusBoxReconciler.reconcile(
            previousBoxes: [],
            issues: [issue(number: 123, title: "Issue A")],
            repository: "owner/repository",
            workingDirectory: "/repos/repository",
            command: "claude",
            commandsByIssue: [123: "codex"],
            retainUnmanagedBoxes: true
        )

        #expect(result.repositoryBoxes.first?.autorun == "codex")
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
