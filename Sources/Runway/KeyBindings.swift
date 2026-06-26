import SwiftUI
import AppKit

/// A keyboard chord: a physical key (matched by keyCode so Option-composed
/// characters don't break it) plus modifier flags.
struct KeyChord: Codable, Equatable {
    var keyCode: UInt16
    var modifiers: UInt   // NSEvent.ModifierFlags rawValue, masked to the four below

    static let relevant: NSEvent.ModifierFlags = [.command, .option, .control, .shift]

    init(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) {
        self.keyCode = keyCode
        self.modifiers = modifiers.intersection(Self.relevant).rawValue
    }

    func matches(_ event: NSEvent) -> Bool {
        event.keyCode == keyCode &&
        event.modifierFlags.intersection(Self.relevant).rawValue == modifiers
    }

    var display: String {
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
        ]
        return map[c] ?? "key\(c)"
    }
}

/// The customizable actions (⌘1–9 "jump to card" stays fixed).
enum AppAction: String, CaseIterable {
    case newBox, closeBox, navigatePrev, navigateNext, reorderUp, reorderDown, accordion, solo, quickTerminal

    var label: String {
        switch self {
        case .newBox:        return "New agent"
        case .closeBox:      return "Close agent"
        case .navigatePrev:  return "Focus previous"
        case .navigateNext:  return "Focus next"
        case .reorderUp:     return "Move agent up"
        case .reorderDown:   return "Move agent down"
        case .accordion:     return "Toggle accordion"
        case .solo:          return "Toggle solo / zoom"
        case .quickTerminal: return "Toggle quick terminal"
        }
    }

    var defaultChord: KeyChord {
        switch self {
        case .newBox:        return KeyChord(keyCode: 45, modifiers: [.command])                       // ⌘N
        case .closeBox:      return KeyChord(keyCode: 13, modifiers: [.command])                       // ⌘W
        case .navigatePrev:  return KeyChord(keyCode: 126, modifiers: [.command, .option])             // ⌘⌥↑
        case .navigateNext:  return KeyChord(keyCode: 125, modifiers: [.command, .option])             // ⌘⌥↓
        case .reorderUp:     return KeyChord(keyCode: 126, modifiers: [.command, .option, .shift])     // ⌘⌥⇧↑
        case .reorderDown:   return KeyChord(keyCode: 125, modifiers: [.command, .option, .shift])     // ⌘⌥⇧↓
        case .accordion:     return KeyChord(keyCode: 0, modifiers: [.command, .option])               // ⌘⌥A
        case .solo:          return KeyChord(keyCode: 36, modifiers: [.command, .option])              // ⌘⌥↩
        case .quickTerminal: return KeyChord(keyCode: 12, modifiers: [.command, .option])              // ⌘⌥Q
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
    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        HStack {
            Text(action.label)
            Spacer()
            Button(recording ? "Press keys…" : bindings.chord(for: action).display) { toggle() }
                .buttonStyle(.bordered)
                .frame(minWidth: 96)
                .monospacedDigit()
            Button { bindings.reset(action) } label: { Image(systemName: "arrow.uturn.backward") }
                .buttonStyle(.borderless)
                .help("Reset to default")
                .disabled(!bindings.isCustom(action))
        }
        .onDisappear(perform: stop)
    }

    private func toggle() {
        if recording { stop(); return }
        recording = true
        bindings.recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { ev in
            if ev.keyCode == 53 { stop(); return nil }   // esc cancels
            // Require at least one of ⌘/⌥/⌃ so a bare key can't hijack typing.
            guard !ev.modifierFlags.intersection([.command, .option, .control]).isEmpty else { return nil }
            bindings.set(KeyChord(keyCode: ev.keyCode, modifiers: ev.modifierFlags), for: action)
            stop()
            return nil
        }
    }
    private func stop() {
        recording = false
        bindings.recording = false
        if let m = monitor { NSEvent.removeMonitor(m); monitor = nil }
    }
}

/// The "Shortcuts" Settings tab.
struct ShortcutSettings: View {
    @Bindable private var bindings = KeyBindings.shared
    var body: some View {
        Form {
            Section {
                ForEach(AppAction.allCases, id: \.self) { KeyRecorderRow(action: $0) }
            } header: {
                Text("Click a shortcut, then press the new keys (Esc to cancel). ⌘1–9 jump to a card.")
            } footer: {
                HStack { Spacer(); Button("Reset all to defaults") { bindings.resetAll() } }
            }
        }
        .formStyle(.grouped)
    }
}
