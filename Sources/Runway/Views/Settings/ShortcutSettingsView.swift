import SwiftUI

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
