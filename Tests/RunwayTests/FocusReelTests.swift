import Foundation
import Testing
@testable import Runway

@Suite("Focus lane")
struct FocusReelTests {
    // MARK: Migration

    @Test("Paginated boards flatten in board order, deduplicated, over the limit")
    func migratesBoards() throws {
        let json = #"{"boards":[[1,2,3,4,5],[6,7,2,8,9],[10,11,12]],"selectedIndex":1}"#
        let reel = try JSONDecoder().decode(FocusReel.self, from: Data(json.utf8))

        #expect(reel.issues == [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12])
    }

    @Test("A saved dictionary of boards migrates every repository")
    func migratesSavedDictionary() throws {
        let json = #"{"a/one":{"boards":[[1],[2,3]],"selectedIndex":0},"b/two":{"boards":[[]],"selectedIndex":0}}"#
        let saved = try JSONDecoder().decode([String: FocusReel].self, from: Data(json.utf8))

        #expect(saved["a/one"]?.issues == [1, 2, 3])
        #expect(saved["b/two"]?.issues == [])
    }

    @Test("A window offset saved by an older version is dropped, the list is not")
    func dropsSavedWindow() throws {
        let json = #"{"issues":[12,31,18,40,22],"offset":3}"#
        let reel = try JSONDecoder().decode(FocusReel.self, from: Data(json.utf8))

        #expect(reel.issues == [12, 31, 18, 40, 22])
    }

    @Test("The list survives persistence")
    func roundTrip() throws {
        let reel = FocusReel(issues: [1, 2, 3, 4, 5, 6])
        let data = try JSONEncoder().encode(reel)
        let restored = try JSONDecoder().decode(FocusReel.self, from: data)

        #expect(restored == reel)
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(object?["boards"] == nil)
        #expect(object?["offset"] == nil)
    }

    @Test("Every issue in the lane is on screen")
    func noWindow() {
        let reel = FocusReel(issues: [12, 31, 18, 40, 22, 35, 9])
        #expect(reel.count == 7)
        #expect(reel.allSet == [12, 31, 18, 40, 22, 35, 9])
        #expect(reel.contains(40))
        #expect(!reel.contains(41))
    }

    @Test("A duplicate never enters the lane twice")
    func deduplicates() {
        var reel = FocusReel(issues: [12, 31, 12])
        #expect(reel.issues == [12, 31])
        reel.replace(with: [31, 12, 31])
        #expect(reel.issues == [31, 12])
    }

    // MARK: Limit

    @Test("The limit blocks adding, unlimited never does, and lowering it evicts nothing")
    func limitEnforcement() {
        #expect(FocusReel.canAdd(count: 9, limit: 10))
        #expect(!FocusReel.canAdd(count: 10, limit: 10))
        #expect(FocusReel.canAdd(count: 500, limit: nil))

        var reel = FocusReel(issues: Array(1...12))
        // Lowering the limit to 5 keeps all twelve but takes no more.
        reel.replace(with: reel.issues)
        #expect(reel.count == 12)
        #expect(!FocusReel.canAdd(count: reel.count, limit: 5))
        reel.replace(with: Array(1...4))
        #expect(FocusReel.canAdd(count: reel.count, limit: 5))
    }

    @Test("Reconciling drops issues that are gone and keeps the order")
    func reconciles() {
        var reel = FocusReel(issues: [4, 1, 3, 2, 5])
        reel.reconcile(available: [1, 2, 4])
        #expect(reel.issues == [4, 1, 2])
    }

    // MARK: Settings

    @Test("The limit setting defaults, clamps, and allows unlimited")
    func settings() {
        let suite = "runway.tests.settings.focusReel"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)

        #expect(SettingsKey.configuredFocusLimit(in: defaults) == 10)

        defaults.set(0, forKey: SettingsKey.focusLimit)
        #expect(SettingsKey.configuredFocusLimit(in: defaults) == nil)
        defaults.set(3, forKey: SettingsKey.focusLimit)
        #expect(SettingsKey.configuredFocusLimit(in: defaults) == 3)
        defaults.set(500, forKey: SettingsKey.focusLimit)
        #expect(SettingsKey.configuredFocusLimit(in: defaults) == FocusReel.limitRange.upperBound)
    }

    // MARK: Workspace

    @MainActor @Test("Only the window's boxes are visible; hidden ones remain mounted")
    func projectsWindow() {
        let workspace = Workspace()
        let first = AgentBox(name: "First", focusRepository: "owner/repo", focusIssueNumber: 1)
        let second = AgentBox(name: "Second", focusRepository: "owner/repo", focusIssueNumber: 2)
        workspace.boxes = [first, second]
        workspace.focusBoardControlsBoxes = true
        workspace.activeFocusRepository = "owner/repo"
        workspace.activeFocusOrder = [1, 2]
        workspace.activeFocusIssueNumbers = [2]

        #expect(workspace.activeBoxes.map(\.id) == [second.id])
        #expect(workspace.boxes.map(\.id) == [first.id, second.id])
    }

    @MainActor @Test("A hidden card's alert asks the reel to reveal it before focusing")
    func revealsHiddenCardForAttention() {
        let workspace = Workspace()
        let feed = GitHubFeed()
        feed.repo = "owner/repo"
        workspace.repositoryFeed = feed
        let visible = AgentBox(name: "Visible", focusRepository: "owner/repo", focusIssueNumber: 1)
        let hidden = AgentBox(name: "Hidden", focusRepository: "owner/repo", focusIssueNumber: 2)
        workspace.boxes = [visible, hidden]
        workspace.focusBoardControlsBoxes = true
        workspace.activeFocusRepository = "owner/repo"
        workspace.activeFocusOrder = [1, 2]
        workspace.activeFocusIssueNumbers = [1]
        workspace.focusedID = visible.id

        workspace.revealAgent(hidden.id, in: "owner/repo")

        #expect(workspace.focusedID == visible.id)
        #expect(workspace.focusIssueRevealRequest?.issueNumber == 2)
        #expect(workspace.focusIssueRevealRequest?.repository == "owner/repo")
    }

    @MainActor @Test("Jumping to a hidden card by number asks the reel to reveal it")
    func jumpRevealsHiddenCard() {
        let workspace = Workspace()
        let boxes = (1...5).map {
            AgentBox(name: "\($0)", focusRepository: "owner/repo", focusIssueNumber: $0)
        }
        workspace.boxes = boxes
        workspace.focusBoardControlsBoxes = true
        workspace.activeFocusRepository = "owner/repo"
        workspace.activeFocusOrder = [1, 2, 3, 4, 5]
        workspace.activeFocusIssueNumbers = [1, 2, 3, 4]
        workspace.focusedID = boxes[0].id

        workspace.focus(index: 4)
        #expect(workspace.focusIssueRevealRequest?.issueNumber == 5)
        #expect(workspace.focusedID == boxes[0].id)

        workspace.focusIssueRevealRequest = nil
        workspace.focus(index: 7)
        #expect(workspace.focusIssueRevealRequest == nil)
    }

    @MainActor @Test("A card scrolled out of the window hands focus to the nearest edge")
    func nearestVisibleBox() {
        let boxes = (1...6).map {
            AgentBox(name: "\($0)", focusRepository: "owner/repo", focusIssueNumber: $0)
        }
        let window = Array(boxes[2...5])
        #expect(Workspace.nearestVisibleBox(to: 1, in: window, order: Array(1...6)) == boxes[2].id)
        #expect(Workspace.nearestVisibleBox(to: nil, in: window, order: Array(1...6)) == nil)
    }
}
