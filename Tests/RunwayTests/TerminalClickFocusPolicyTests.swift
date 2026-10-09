import Foundation
import Testing
@testable import Runway

@Suite("Terminal click focus")
struct TerminalClickFocusPolicyTests {
    @Test("An unfocused terminal only changes focus when the click is released")
    func focusesOnRelease() {
        var policy = TerminalClickFocusPolicy()
        let window = NSObject()
        let boxID = UUID()
        let target = TerminalClickFocusPolicy.Target(
            window: ObjectIdentifier(window), boxID: boxID
        )

        #expect(policy.mouseDown(
            over: target, focusedID: UUID(), at: CGPoint(x: 10, y: 10)
        ) == .passThrough)
        #expect(policy.mouseUp(over: target) == .focus(boxID))
    }

    @Test("Dragging to select text does not expand the unfocused terminal")
    func dragSelectsWithoutFocusing() {
        var policy = TerminalClickFocusPolicy()
        let window = NSObject()
        let focusedID = UUID()
        let target = TerminalClickFocusPolicy.Target(
            window: ObjectIdentifier(window), boxID: UUID()
        )

        #expect(policy.mouseDown(
            over: target, focusedID: focusedID, at: CGPoint(x: 10, y: 10)
        ) == .passThrough)
        policy.mouseDragged(in: ObjectIdentifier(window), to: CGPoint(x: 30, y: 10))
        #expect(policy.mouseUp(over: target) == .restoreKeyboard(focusedID))
    }

    @Test("A held click released elsewhere does not change focus")
    func cancelledClick() {
        var policy = TerminalClickFocusPolicy()
        let window = NSObject()
        let otherWindow = NSObject()
        let boxID = UUID()
        let target = TerminalClickFocusPolicy.Target(
            window: ObjectIdentifier(window), boxID: boxID
        )
        let otherTarget = TerminalClickFocusPolicy.Target(
            window: ObjectIdentifier(otherWindow), boxID: boxID
        )

        let focusedID = UUID()
        #expect(policy.mouseDown(
            over: target, focusedID: focusedID, at: .zero
        ) == .passThrough)
        #expect(policy.mouseUp(over: otherTarget) == .restoreKeyboard(focusedID))
        #expect(policy.mouseUp(over: target) == .passThrough)
    }

    @Test("A terminal already in focus receives its clicks normally")
    func focusedTerminalPassesThrough() {
        var policy = TerminalClickFocusPolicy()
        let boxID = UUID()
        let target = TerminalClickFocusPolicy.Target(
            window: ObjectIdentifier(NSObject()), boxID: boxID
        )

        #expect(policy.mouseDown(over: target, focusedID: boxID, at: .zero) == .passThrough)
        #expect(policy.mouseUp(over: target) == .passThrough)
    }
}
