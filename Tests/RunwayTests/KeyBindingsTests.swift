import AppKit
import Testing
@testable import Runway

@Suite("Key bindings")
struct KeyBindingsTests {
    @Test("Close window defaults to Command-Shift-W")
    func closeWindowDefault() {
        #expect(AppAction.closeWindow.label == "Close window")
        #expect(
            AppAction.closeWindow.defaultChord
                == KeyChord(keyCode: 13, modifiers: [.command, .shift])
        )
    }
}
