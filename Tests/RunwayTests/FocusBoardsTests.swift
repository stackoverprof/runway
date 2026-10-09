import Foundation
import Testing
@testable import Runway

@Suite("Paginated Focus boards")
struct FocusBoardsTests {
    @Test("A new board starts empty without disturbing the first five issues")
    func createsIndependentBoard() {
        var boards = FocusBoards(boards: [[1, 2, 3, 4, 5]])
        boards.create()

        #expect(boards.count == 2)
        #expect(boards.selectedIndex == 1)
        #expect(boards.selected.isEmpty)
        #expect(boards.all == [1, 2, 3, 4, 5])

        boards.replaceSelected(with: [6, 7])
        boards.select(0)
        #expect(boards.selected == [1, 2, 3, 4, 5])
        #expect(boards.all == [1, 2, 3, 4, 5, 6, 7])
    }

    @Test("Each board holds at most five and an issue appears on only one board")
    func capsAndDeduplicates() {
        var boards = FocusBoards(boards: [[1, 2, 3, 4, 5, 6], [5, 6, 7, 8, 9, 10]])

        #expect(boards.boards[0] == [1, 2, 3, 4, 5])
        #expect(boards.boards[1] == [6, 7, 8, 9, 10])
        #expect(boards.boardIndex(containing: 7) == 1)

        boards.select(1)
        boards.replaceSelected(with: [1, 6, 6, 7])
        #expect(boards.selected == [6, 7])
    }

    @Test("Revalidation removes unavailable issues without changing the selected board")
    func reconcilesEveryBoard() {
        var boards = FocusBoards(boards: [[1, 2], [3, 4]], selectedIndex: 1)
        boards.reconcile(available: [1, 3])

        #expect(boards.boards == [[1], [3]])
        #expect(boards.selectedIndex == 1)
    }

    @Test("Board membership and selection survive persistence")
    func roundTrip() throws {
        let boards = FocusBoards(boards: [[1, 2], [3]], selectedIndex: 1)
        let restored = try JSONDecoder().decode(FocusBoards.self, from: JSONEncoder().encode(boards))

        #expect(restored == boards)
    }

    @MainActor @Test("Only the selected board's boxes are visible; others remain mounted")
    func projectsSelectedBoard() {
        let workspace = Workspace()
        let first = AgentBox(name: "First", focusRepository: "owner/repo", focusIssueNumber: 1)
        let second = AgentBox(name: "Second", focusRepository: "owner/repo", focusIssueNumber: 2)
        workspace.boxes = [first, second]
        workspace.focusBoardControlsBoxes = true
        workspace.activeFocusRepository = "owner/repo"
        workspace.activeFocusIssueNumbers = [2]

        #expect(workspace.activeBoxes.map(\.id) == [second.id])
        #expect(workspace.boxes.map(\.id) == [first.id, second.id])
    }

    @MainActor @Test("A hidden board's alert requests that board before focusing its terminal")
    func revealsHiddenBoardForAttention() {
        let workspace = Workspace()
        let feed = GitHubFeed()
        feed.repo = "owner/repo"
        workspace.repositoryFeed = feed
        let visible = AgentBox(name: "Visible", focusRepository: "owner/repo", focusIssueNumber: 1)
        let hidden = AgentBox(name: "Hidden", focusRepository: "owner/repo", focusIssueNumber: 2)
        workspace.boxes = [visible, hidden]
        workspace.focusBoardControlsBoxes = true
        workspace.activeFocusRepository = "owner/repo"
        workspace.activeFocusIssueNumbers = [1]
        workspace.focusedID = visible.id

        workspace.revealAgent(hidden.id, in: "owner/repo")

        #expect(workspace.focusedID == visible.id)
        #expect(workspace.focusIssueRevealRequest?.issueNumber == 2)
        #expect(workspace.focusIssueRevealRequest?.repository == "owner/repo")
    }
}
