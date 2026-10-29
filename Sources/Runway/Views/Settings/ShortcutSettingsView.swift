import SwiftUI

/// The "Shortcuts" Settings tab.
struct ShortcutSettings: View {
    @Bindable private var bindings = KeyBindings.shared
    @Bindable private var commands = CustomCommands.shared
    var body: some View {
        Form {
            Section {
                ForEach(commands.commands) { CustomCommandRow(command: $0) }
                Button("Add command") { commands.add() }
                    .pointerCursor()
            } header: {
                Text("Commands")
            } footer: {
                Text("The shortcut runs the command in the background, in the repository on screen, and a banner shows when it starts and ends. Runway's lanes refresh when it finishes. For a Claude task, use claude -p \"your prompt\".")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

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
