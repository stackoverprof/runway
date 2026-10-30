import SwiftUI
import AppKit

/// A keyboard chord: a physical key (matched by keyCode so Option-composed
/// characters don't break it) plus modifier flags.
struct KeyChord: Codable, Equatable {
    static let functionKeyCode: UInt16 = 63

    var keyCode: UInt16
    var modifiers: UInt   // NSEvent.ModifierFlags rawValue, masked to the four below

    static let relevant: NSEvent.ModifierFlags = [.command, .option, .control, .shift]

    init(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) {
        self.keyCode = keyCode
        self.modifiers = modifiers.intersection(Self.relevant).rawValue
    }

    func matches(_ event: NSEvent) -> Bool {
        if keyCode == Self.functionKeyCode {
            guard event.type == .flagsChanged,
                  event.modifierFlags.contains(.function),
                  event.modifierFlags.intersection(Self.relevant).rawValue == modifiers else {
                return false
            }
            let leftShiftKeyCode: UInt16 = 56
            let rightShiftKeyCode: UInt16 = 60
            return event.keyCode == Self.functionKeyCode
                || (modifiers == NSEvent.ModifierFlags.shift.rawValue
                    && [leftShiftKeyCode, rightShiftKeyCode].contains(event.keyCode))
        }
        return event.keyCode == keyCode &&
        event.modifierFlags.intersection(Self.relevant).rawValue == modifiers
    }

    var display: String {
        if keyCode == Self.functionKeyCode {
            return modifiers == NSEvent.ModifierFlags.shift.rawValue ? "fn⇧" : "fn"
        }
        var s = ""
        let m = NSEvent.ModifierFlags(rawValue: modifiers)
        if m.contains(.control) { s += "⌃" }
        if m.contains(.option)  { s += "⌥" }
        if m.contains(.shift)   { s += "⇧" }
        if m.contains(.command) { s += "⌘" }
        return s + Self.keyName(keyCode)
    }

    static func keyName(_ c: UInt16) -> String {
        let map: [UInt16: String] = [
            0:"A",1:"S",2:"D",3:"F",4:"H",5:"G",6:"Z",7:"X",8:"C",9:"V",11:"B",12:"Q",13:"W",
            14:"E",15:"R",16:"Y",17:"T",18:"1",19:"2",20:"3",21:"4",22:"6",23:"5",24:"=",25:"9",
            26:"7",28:"8",29:"0",31:"O",32:"U",34:"I",35:"P",37:"L",38:"J",40:"K",45:"N",46:"M",
            36:"↩",48:"⇥",49:"Space",51:"⌫",53:"esc",123:"←",124:"→",125:"↓",126:"↑",
            47:".",43:",",44:"/",27:"-",30:"]",33:"[",39:"'",41:";",42:"\\",50:"`",
            63:"fn",
        ]
        return map[c] ?? "key\(c)"
    }
}

/// The customizable actions (⌘1–9 "jump to card" stays fixed).
enum AppAction: String, CaseIterable {
    case closeWindow, repoPicker, quickTerminal

    var label: String {
        switch self {
        case .closeWindow:   return "Close window"
        case .repoPicker:    return "Switch repository"
        case .quickTerminal: return "Toggle ATC panel"
        }
    }

    var defaultChord: KeyChord {
        switch self {
        case .closeWindow:   return KeyChord(keyCode: 13, modifiers: [.command, .shift])   // ⌘⇧W
        case .repoPicker:    return KeyChord(keyCode: 15, modifiers: [.command])           // ⌘R
        case .quickTerminal: return KeyChord(keyCode: 12, modifiers: [.command, .option])  // ⌘⌥Q
        }
    }
}

@MainActor @Observable final class KeyBindings {
    static let shared = KeyBindings()
    /// True while the Settings recorder is capturing, so the global monitor stands down.
    var recording = false
    private var custom: [AppAction: KeyChord] = [:]
    private static let key = "runway.keybindings"

    private init() { load() }

    func chord(for a: AppAction) -> KeyChord { custom[a] ?? a.defaultChord }
    func isCustom(_ a: AppAction) -> Bool { custom[a] != nil }
    func set(_ chord: KeyChord, for a: AppAction) { custom[a] = chord; save() }
    func reset(_ a: AppAction) { custom[a] = nil; save() }
    func resetAll() { custom = [:]; save() }

    /// Which action a key event triggers (used by the global key monitor).
    func action(for event: NSEvent) -> AppAction? {
        AppAction.allCases.first { chord(for: $0).matches(event) }
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: Self.key),
              let dict = try? JSONDecoder().decode([String: KeyChord].self, from: data) else { return }
        for (k, v) in dict { if let a = AppAction(rawValue: k) { custom[a] = v } }
    }
    private func save() {
        var dict: [String: KeyChord] = [:]
        for (a, c) in custom { dict[a.rawValue] = c }
        if let data = try? JSONEncoder().encode(dict) { UserDefaults.standard.set(data, forKey: Self.key) }
    }
}

/// One editable shortcut row: shows the chord, click to record a new one.
struct KeyRecorderRow: View {
    let action: AppAction
    @Bindable private var bindings = KeyBindings.shared

    var body: some View {
        HStack {
            Text(action.label)
            Spacer()
            ChordRecorderButton(display: bindings.chord(for: action).display) {
                bindings.set($0, for: action)
            }
            Button { bindings.reset(action) } label: { Image(systemName: "arrow.uturn.backward") }
                .buttonStyle(.borderless)
                .help("Reset to default")
                .disabled(!bindings.isCustom(action))
                .pointerCursor()
        }
    }
}

/// Click, then press a chord. Esc cancels. Shared by the built-in actions and
/// custom commands.
struct ChordRecorderButton: View {
    let display: String
    let onRecord: (KeyChord) -> Void
    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        Button(recording ? "Press keys…" : display) { toggle() }
            .buttonStyle(.bordered)
            .frame(minWidth: 96)
            .monospacedDigit()
            .pointerCursor()
            .onDisappear(perform: stop)
    }

    private func toggle() {
        if recording { stop(); return }
        recording = true
        KeyBindings.shared.recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { ev in
            if ev.keyCode == 53 { stop(); return nil }   // esc cancels
            if ev.type == .flagsChanged,
               ev.modifierFlags.contains(.function),
               ev.modifierFlags.intersection(KeyChord.relevant) == .shift,
               KeyChord(keyCode: KeyChord.functionKeyCode, modifiers: [.shift]).matches(ev) {
                onRecord(KeyChord(keyCode: KeyChord.functionKeyCode, modifiers: [.shift]))
                stop()
                return nil
            }
            guard ev.type == .keyDown else { return ev }
            // Require at least one of ⌘/⌥/⌃ so a bare key can't hijack typing.
            guard !ev.modifierFlags.intersection([.command, .option, .control]).isEmpty else { return nil }
            onRecord(KeyChord(keyCode: ev.keyCode, modifiers: ev.modifierFlags))
            stop()
            return nil
        }
    }

    private func stop() {
        recording = false
        KeyBindings.shared.recording = false
        if let m = monitor { NSEvent.removeMonitor(m); monitor = nil }
    }
}
