import Foundation
import Testing
@testable import Runway

@Suite("Agent attention notification routing")
struct AgentAttentionRoutingTests {
    @Test("Focus notification keeps the exact box and repository")
    func focusNotificationRoundTrip() {
        let id = UUID()
        let target = AgentAttentionTarget.box(id, repository: "owner/other-repo")

        #expect(AgentAttentionTarget(userInfo: target.userInfo) == target)
    }

    @Test("Quick notification keeps the exact durable tab, not its current index")
    func quickNotificationRoundTrip() {
        let target = AgentAttentionTarget.quick(root: "durable-root-2")

        #expect(AgentAttentionTarget(userInfo: target.userInfo) == target)
        #expect(AgentAttentionTarget(userInfo: [:]) == nil)
    }

    @MainActor @Test("Opening a Quick notification requests its tab and opens the panel")
    func opensQuickTab() {
        let workspace = Workspace()
        let root = QuickTerminalSession.tabRoots()[0]
        workspace.quickVisible = false
        let alert = AttentionAlert(
            id: QuickTerminalSession.boxID(root: root),
            target: .quick(root: root),
            location: "Quick tab 1",
            title: "Quick Agent"
        )
        workspace.attentionAlerts = [alert]

        workspace.openAttention(alert)

        #expect(workspace.quickVisible)
        #expect(workspace.quickTabRequest?.action == .selectRoot(root))
        #expect(workspace.attentionAlerts.isEmpty)
    }

    @MainActor @Test("Opening a Focus notification selects the exact visible terminal")
    func opensFocusBox() {
        let workspace = Workspace()
        let first = AgentBox(name: "First")
        let target = AgentBox(name: "Target")
        workspace.boxes = [first, target]
        workspace.focusBoardControlsBoxes = false
        workspace.focusedID = first.id

        workspace.openAttentionTarget(.box(target.id, repository: nil))

        #expect(workspace.focusedID == target.id)
    }

    @MainActor @Test("A parked Focus box is not focused before its repository is mounted")
    func waitsForRepositoryProjection() {
        let workspace = Workspace()
        let feed = GitHubFeed()
        feed.repo = "owner/visible"
        workspace.repositoryFeed = feed
        let visible = AgentBox(name: "Visible", focusRepository: "owner/visible")
        let parked = AgentBox(name: "Parked", focusRepository: "owner/parked")
        workspace.boxes = [visible, parked]
        workspace.focusBoardControlsBoxes = true
        workspace.activeFocusRepository = "owner/visible"
        workspace.focusedID = visible.id

        workspace.revealAgent(parked.id, in: "owner/parked")

        #expect(workspace.focusedID == visible.id)
        #expect(workspace.selectedTab == .runway)
    }
}
