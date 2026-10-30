import SwiftUI

/// The "Shortcuts" Settings tab.
struct ShortcutSettings: View {
    @Bindable private var bindings = KeyBindings.shared
    var body: some View {
        Form {
            Section {
                ForEach(AppAction.allCases, id: \.self) { KeyRecorderRow(action: $0) }
            } header: {
                Text("Click a shortcut, then press the new keys (Esc to cancel). ⌘⌥1–2 jump to a tab, ⌘⌥[ / ⌘⌥] cycle tabs, and ⌘⌥, / ⌘⌥. step through that tab's own options.")
            }
        }
        .formStyle(.grouped)
    }
}
