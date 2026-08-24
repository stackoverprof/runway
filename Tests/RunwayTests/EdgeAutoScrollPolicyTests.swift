import Foundation
import Testing
@testable import Runway

@Suite("Edge auto-scroll policy")
struct EdgeAutoScrollPolicyTests {
    private let lane = CGRect(x: 0, y: 100, width: 300, height: 400)

    @Test("The middle of the lane does not scroll")
    func calmMiddle() {
        #expect(EdgeAutoScrollPolicy.step(pointerY: 300, in: lane) == 0)
    }

    @Test("Dragging to the bottom edge scrolls toward the end of the list")
    func bottomEdgeScrollsDown() {
        let step = EdgeAutoScrollPolicy.step(pointerY: lane.maxY - 4, in: lane)
        #expect(step > 0)
    }

    @Test("Dragging to the top edge scrolls back up")
    func topEdgeScrollsUp() {
        let step = EdgeAutoScrollPolicy.step(pointerY: lane.minY + 4, in: lane)
        #expect(step < 0)
    }

    @Test("Speed ramps with depth and never exceeds the cap")
    func rampsAndClamps() {
        let shallow = EdgeAutoScrollPolicy.step(pointerY: lane.maxY - 40, in: lane)
        let deep = EdgeAutoScrollPolicy.step(pointerY: lane.maxY - 2, in: lane)
        #expect(deep > shallow)
        let overshoot = EdgeAutoScrollPolicy.step(pointerY: lane.maxY + 500, in: lane)
        #expect(overshoot == EdgeAutoScrollPolicy.maxStep)
    }

    @Test("A lane too short to have two hot zones never auto-scrolls")
    func shortLane() {
        let short = CGRect(x: 0, y: 0, width: 300, height: 40)
        #expect(EdgeAutoScrollPolicy.step(pointerY: 39, in: short) == 0)
    }
}
