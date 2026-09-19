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
