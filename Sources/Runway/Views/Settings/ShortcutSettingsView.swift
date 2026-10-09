import SwiftUI

/// The "Shortcuts" Settings tab.
struct ShortcutSettings: View {
    @Bindable private var bindings = KeyBindings.shared
    var body: some View {
        Form {
            Section {
                ForEach(AppAction.allCases, id: \.self) { KeyRecorderRow(action: $0) }
            } header: {
                Text("Click a shortcut, then press the new keys (Esc to cancel). ⌘1–9 jump to a card, ⌘⌥1–3 to a tab, ⌘⌥[ / ⌘⌥] cycle tabs, and ⌘⌥, / ⌘⌥. step through that tab's own options.")
            } footer: {
                VStack(alignment: .trailing, spacing: 8) {
                    Text("Fn⇧ toggles the quick terminal while Runway is active. If macOS still opens Emoji & Symbols, set “Press fn key to” to “Do Nothing” in Keyboard settings.")
                        .frame(maxWidth: .infinity, alignment: .leading)
                    HStack {
                        Spacer()
                        Button("Reset all to defaults") { bindings.resetAll() }
                            .pointerCursor()
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}
