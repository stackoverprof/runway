import SwiftUI

/// The "Shortcuts" Settings tab.
///
/// Every verb is a row you can rebind. The number families are not rows:
/// they are positions, nine of them at a time, and there is nothing to
/// record. They are stated instead, at the bottom, because a shortcut you
/// cannot find is a shortcut you do not have.
struct ShortcutSettings: View {
    @Bindable private var bindings = KeyBindings.shared

    private var groups: [String] {
        var seen: [String] = []
        for action in AppAction.allCases where !seen.contains(action.group) {
            seen.append(action.group)
        }
        return seen
    }

    var body: some View {
        Form {
            ForEach(groups, id: \.self) { group in
                Section(group) {
                    ForEach(AppAction.allCases.filter { $0.group == group }, id: \.self) {
                        KeyRecorderRow(action: $0)
                    }
                }
            }

            Section {
                fixed("⌘1-9", "The nth flight in the list")
                fixed("⌘⌃1-9", "The nth crew of the flight")
                fixed("⌘⌥1-3", "Jump to a tab")
                fixed("⌘⌥⇧1-5", "Jump to one of that tab's options")
                fixed("⌘⌥[ ⌘⌥]", "Step through the tabs")
                fixed("⌘⌥, ⌘⌥.", "Step through that tab's options")
                fixed("⌘F", "Search the tab in front")
            } header: {
                Text("By position")
            } footer: {
                Text("Click a shortcut above, then press the new keys. Esc cancels.")
            }
        }
        .formStyle(.grouped)
    }

    private func fixed(_ chord: String, _ label: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(chord)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
        }
    }
}
