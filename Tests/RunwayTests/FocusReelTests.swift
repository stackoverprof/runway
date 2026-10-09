import Foundation
import Testing
@testable import Runway

@Suite("Focus reel")
struct FocusReelTests {
    // MARK: Migration

    @Test("Paginated boards flatten in board order, deduplicated, over the limit")
    func migratesBoards() throws {
        let json = #"{"boards":[[1,2,3,4,5],[6,7,2,8,9],[10,11,12]],"selectedIndex":1}"#
        let reel = try JSONDecoder().decode(FocusReel.self, from: Data(json.utf8))

        #expect(reel.issues == [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12])
        // The window opens where the selected board began.
        #expect(reel.offset == 5)
        #expect(reel.visible == [6, 7, 8, 9])
    }

    @Test("A saved dictionary of boards migrates every repository")
    func migratesSavedDictionary() throws {
        let json = #"{"a/one":{"boards":[[1],[2,3]],"selectedIndex":0},"b/two":{"boards":[[]],"selectedIndex":0}}"#
        let saved = try JSONDecoder().decode([String: FocusReel].self, from: Data(json.utf8))

        #expect(saved["a/one"]?.issues == [1, 2, 3])
        #expect(saved["a/one"]?.offset == 0)
        #expect(saved["b/two"]?.issues == [])
    }

    @Test("A selected board near the end clamps the window to a full one")
    func migrationClampsOffset() {
        let reel = FocusReel.migrating(boards: [[1, 2, 3, 4, 5], [6]], selectedIndex: 1)
        #expect(reel.offset == 2)
        #expect(reel.visible == [3, 4, 5, 6])
    }

    @Test("The list and offset survive persistence; the window size does not")
    func roundTrip() throws {
        let reel = FocusReel(issues: [1, 2, 3, 4, 5, 6], offset: 2, visibleCount: 3)
        let data = try JSONEncoder().encode(reel)
        var restored = try JSONDecoder().decode(FocusReel.self, from: data)

        #expect(restored.issues == [1, 2, 3, 4, 5, 6])
        #expect(restored.offset == 2)
        #expect(restored.visibleCount == FocusReel.defaultVisibleCount)
        restored.setVisibleCount(3)
        #expect(restored == reel)
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(object?["boards"] == nil)
    }

    // MARK: Window

    @Test("Hidden counts on each side of the window")
    func hiddenCounts() {
        let reel = FocusReel(issues: [12, 31, 18, 40, 22, 35, 9], offset: 1)
        #expect(reel.visible == [31, 18, 40, 22])
        #expect(reel.hiddenAbove == 1)
        #expect(reel.hiddenBelow == 2)
        #expect(reel.firstHiddenBelow == 35)

        let short = FocusReel(issues: [1, 2])
        #expect(short.hiddenAbove == 0)
        #expect(short.hiddenBelow == 0)
        #expect(short.firstHiddenBelow == nil)
    }

    @Test("Shifting moves one card at a time and stops at either end")
    func shiftsAndClamps() {
        var reel = FocusReel(issues: Array(1...6))
        let result1 = reel.shift(by: -1)
        #expect(!result1)
        let result2 = reel.shift(by: 1)
        #expect(result2)
        #expect(reel.visible == [2, 3, 4, 5])
        let result3 = reel.shift(by: 1)
        #expect(result3)
        let result4 = reel.shift(by: 1)
        #expect(!result4)
        #expect(reel.offset == 2)
        reel.shift(by: -10)
        #expect(reel.offset == 0)
    }

    @Test("The offset clamps when the list shrinks, grows, or the window resizes")
    func clampsOnMembershipAndSize() {
        var reel = FocusReel(issues: Array(1...8), offset: 4)
        #expect(reel.visible == [5, 6, 7, 8])

        reel.replace(with: [1, 2, 3, 4, 5, 6])
        #expect(reel.offset == 2)
        #expect(reel.visible == [3, 4, 5, 6])

        reel.replace(with: [1, 2])
        #expect(reel.offset == 0)

        reel.replace(with: Array(1...10))
        #expect(reel.offset == 0)

        reel.shift(by: 6)
        reel.setVisibleCount(6)
        #expect(reel.offset == 4)
        #expect(reel.visible == [5, 6, 7, 8, 9, 10])

        reel.setVisibleCount(0)
        #expect(reel.visibleCount == 1)
    }

    @Test("Revealing an issue slides the window just far enough to include it")
    func revealShiftsWindow() {
        var reel = FocusReel(issues: Array(1...10), offset: 3)
        let result5 = reel.reveal(5)
        #expect(!result5)
        #expect(reel.offset == 3)

        let result6 = reel.reveal(9)
        #expect(result6)
        #expect(reel.visible == [6, 7, 8, 9])

        let result7 = reel.reveal(2)
        #expect(result7)
        #expect(reel.visible == [2, 3, 4, 5])

        let result8 = reel.reveal(99)
        #expect(!result8)
    }

    @Test("Dragging over an edge carries the card into the revealed spot")
    func shiftCarryingDraggedCard() {
        var down = FocusReel(issues: Array(1...8))
        let result9 = down.shift(by: 1, carrying: 2)
        #expect(result9)
        #expect(down.visible == [3, 4, 5, 2])
        #expect(down.issues == [1, 3, 4, 5, 2, 6, 7, 8])

        var up = FocusReel(issues: Array(1...8), offset: 2)
        let result10 = up.shift(by: -1, carrying: 4)
        #expect(result10)
        #expect(up.visible == [4, 2, 3, 5])
        #expect(up.issues.count == 8)

        var top = FocusReel(issues: Array(1...8))
        let result11 = top.shift(by: -1, carrying: 2)
        #expect(!result11)
        #expect(top.issues == Array(1...8))
    }

    @Test("Sliding the window never changes Focus membership")
    func windowChangesAreNotExits() {
        var reel = FocusReel(issues: [12, 31, 18, 40, 22, 35, 9])
        let members = reel.allSet
        reel.shift(by: 2)
        reel.reveal(12)
        reel.setVisibleCount(2)
        reel.shift(by: 1, carrying: 31)
        #expect(reel.allSet == members)
        #expect(reel.count == 7)
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
        var reel = FocusReel(issues: [4, 1, 3, 2, 5], offset: 1)
        reel.reconcile(available: [1, 2, 4])
        #expect(reel.issues == [4, 1, 2])
        #expect(reel.offset == 0)
    }

    // MARK: Settings

    @Test("Window size and limit settings default, clamp, and allow unlimited")
    func settings() {
        let suite = "runway.tests.settings.focusReel"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)

        #expect(SettingsKey.configuredFocusVisibleCount(in: defaults) == 4)
        #expect(SettingsKey.configuredFocusLimit(in: defaults) == 10)

        defaults.set(0, forKey: SettingsKey.focusLimit)
        #expect(SettingsKey.configuredFocusLimit(in: defaults) == nil)
        defaults.set(3, forKey: SettingsKey.focusLimit)
        #expect(SettingsKey.configuredFocusLimit(in: defaults) == 3)

        defaults.set(40, forKey: SettingsKey.focusVisibleCount)
        #expect(SettingsKey.configuredFocusVisibleCount(in: defaults) == 9)
        defaults.set(-2, forKey: SettingsKey.focusVisibleCount)
        #expect(SettingsKey.configuredFocusVisibleCount(in: defaults) == 1)
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

@Suite("Focus reel scrolling")
struct FocusReelScrollStepperTests {
    @Test("A mouse wheel notch is one card, rate-limited")
    func wheelNotches() {
        var stepper = FocusReelScrollStepper()
        let result12 = stepper.step(deltaY: -1, precise: false, isMomentum: false, gestureBegan: false, timestamp: 0)
        #expect(result12 == 1)
        let result13 = stepper.step(deltaY: -1, precise: false, isMomentum: false, gestureBegan: false, timestamp: 0.01)
        #expect(result13 == 0)
        let result14 = stepper.step(deltaY: 3, precise: false, isMomentum: false, gestureBegan: false, timestamp: 0.2)
        #expect(result14 == -1)
    }

    @Test("Trackpad travel steps once per threshold, never mid-card")
    func trackpadThreshold() {
        var stepper = FocusReelScrollStepper()
        let result15 = stepper.step(deltaY: -10, precise: true, isMomentum: false, gestureBegan: true, timestamp: 0)
        #expect(result15 == 0)
        let result16 = stepper.step(deltaY: -10, precise: true, isMomentum: false, gestureBegan: false, timestamp: 0.01)
        #expect(result16 == 0)
        let result17 = stepper.step(deltaY: -10, precise: true, isMomentum: false, gestureBegan: false, timestamp: 0.02)
        #expect(result17 == 1)
        // Inside the cooldown a fast swipe cannot step again.
        let result18 = stepper.step(deltaY: -60, precise: true, isMomentum: false, gestureBegan: false, timestamp: 0.05)
        #expect(result18 == 0)
        let result19 = stepper.step(deltaY: -1, precise: true, isMomentum: false, gestureBegan: false, timestamp: 0.3)
        #expect(result19 == 1)
        // Reversing direction discards travel banked the other way.
        let result20 = stepper.step(deltaY: 20, precise: true, isMomentum: false, gestureBegan: false, timestamp: 0.6)
        #expect(result20 == 0)
        let result21 = stepper.step(deltaY: 10, precise: true, isMomentum: false, gestureBegan: false, timestamp: 0.61)
        #expect(result21 == -1)
    }

    @Test("Momentum after a flick is ignored")
    func ignoresMomentum() {
        var stepper = FocusReelScrollStepper()
        let result22 = stepper.step(deltaY: -30, precise: true, isMomentum: false, gestureBegan: true, timestamp: 0)
        #expect(result22 == 1)
        for tick in 1...40 {
            let result = stepper.step(
                deltaY: -80, precise: true, isMomentum: true, gestureBegan: false,
                timestamp: Double(tick) * 0.05
            )
            #expect(result == 0)
        }
    }
}
