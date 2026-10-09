import AppKit
import Testing
@testable import Runway

@Suite("Key bindings")
struct KeyBindingsTests {
    @Test("Quick terminal defaults to Command-Option-Q")
    func quickTerminalDefault() {
        let chord = AppAction.quickTerminal.defaultChord

        #expect(chord.keyCode == 12)
        #expect(chord.display == "⌥⌘Q")
        #expect(chord.modifiers == NSEvent.ModifierFlags([.command, .option]).rawValue)
    }

    @Test("Fn-Shift matches whichever key completes the chord")
    func functionShiftMatchesEitherOrder() {
        let chord = KeyChord(keyCode: KeyChord.functionKeyCode, modifiers: [.shift])
        let fnPressedLast = NSEvent.keyEvent(
            with: .flagsChanged,
            location: .zero,
            modifierFlags: [.function, .shift],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "",
            charactersIgnoringModifiers: "",
            isARepeat: false,
            keyCode: KeyChord.functionKeyCode
        )!
        let shiftPressedLast = NSEvent.keyEvent(
            with: .flagsChanged,
            location: .zero,
            modifierFlags: [.function, .shift],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "",
            charactersIgnoringModifiers: "",
            isARepeat: false,
            keyCode: 56
        )!
        let fnOnly = NSEvent.keyEvent(
            with: .flagsChanged,
            location: .zero,
            modifierFlags: [.function],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "",
            charactersIgnoringModifiers: "",
            isARepeat: false,
            keyCode: KeyChord.functionKeyCode
        )!
        let release = NSEvent.keyEvent(
            with: .flagsChanged,
            location: .zero,
            modifierFlags: [.shift],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "",
            charactersIgnoringModifiers: "",
            isARepeat: false,
            keyCode: KeyChord.functionKeyCode
        )!
        let modifiedPress = NSEvent.keyEvent(
            with: .flagsChanged,
            location: .zero,
            modifierFlags: [.function, .command],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "",
            charactersIgnoringModifiers: "",
            isARepeat: false,
            keyCode: KeyChord.functionKeyCode
        )!

        #expect(chord.matches(fnPressedLast))
        #expect(chord.matches(shiftPressedLast))
        #expect(!chord.matches(fnOnly))
        #expect(!chord.matches(release))
        #expect(!chord.matches(modifiedPress))
    }

    @Test("Close window defaults to Command-Shift-W")
    func closeWindowDefault() {
        #expect(AppAction.closeWindow.label == "Close window")
        #expect(
            AppAction.closeWindow.defaultChord
                == KeyChord(keyCode: 13, modifiers: [.command, .shift])
        )
    }
}
