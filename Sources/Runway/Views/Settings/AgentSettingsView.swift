import SwiftUI

/// What runs inside a terminal, whether it keeps its conversation, and how it
/// gets your attention.
struct AgentSettings: View {
    @AppStorage(SettingsKey.agentCommandEnabled) private var agentCommandEnabled = false
    @AppStorage(SettingsKey.agentCommand) private var agentCommand = "claude"
    @AppStorage(SettingsKey.issueAgentSessionsEnabled) private var issueAgentSessionsEnabled = true
    @AppStorage(SettingsKey.soundEnabled) private var soundEnabled = true
    @AppStorage(SettingsKey.alertSound) private var alertSound = "Glass"
    @AppStorage(SettingsKey.bannerWhileActive) private var bannerWhileActive = false
    @AppStorage(SettingsKey.focusVisibleCount) private var focusVisibleCount = FocusReel.defaultVisibleCount
    @AppStorage(SettingsKey.focusLimit) private var focusLimit = FocusReel.defaultLimit
    @State private var agentCommandChoice = "claude"

    private let sounds = ["Glass", "Ping", "Submarine", "Hero", "Pop", "Funk", "Blow"]
    private static let focusLimitChoices = [3, 5, 8, 10, 12, 15, 20, 25, 30]

    /// The fixed choices, plus a hand-edited value so the picker never blanks.
    private var focusLimitOptions: [Int] {
        let choices = Self.focusLimitChoices
        guard focusLimit > 0, !choices.contains(focusLimit) else { return choices }
        return (choices + [focusLimit]).sorted()
    }

    var body: some View {
        Form {
            Section("Focus") {
                Stepper(
                    "Terminals on screen: \(focusVisibleCount)",
                    value: $focusVisibleCount,
                    in: FocusReel.visibleCountRange
                )
                .pointerCursor()
                Picker("Most issues in Focus", selection: $focusLimit) {
                    ForEach(focusLimitOptions, id: \.self) { Text("\($0)").tag($0) }
                    Divider()
                    Text("Unlimited").tag(0)
                }
                .pointerCursor()
                Text("Focus is one list seen through a window of this many cards. Cards outside the window keep their terminals running; scroll the list or use the arrows above and below it to bring them on screen. Lowering the limit never removes issues, it only stops new ones until Focus is under it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Command") {
                Toggle("Run command in each agent", isOn: $agentCommandEnabled)
                    .pointerCursor()
                Picker("Command", selection: $agentCommandChoice) {
                    Text("Claude").tag("claude")
                    Text("Codex").tag("codex")
                    Text("Agent").tag("agent")
                    Text("Custom…").tag("custom")
                }
                    .disabled(!agentCommandEnabled)
                    .pointerCursor()

                if agentCommandChoice == "custom" {
                    TextField("Custom command", text: $agentCommand)
                        .disabled(!agentCommandEnabled)
                }

                Text("Runs automatically when a Focus terminal opens, when you reopen the app, and in the quick terminal. Leave unchecked for a plain shell.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Conversations") {
                Toggle("Resume Focus conversations", isOn: $issueAgentSessionsEnabled)
                    .disabled(!agentCommandEnabled)
                    .pointerCursor()

                Text("Binds each Focus issue to one agent conversation, so its terminal comes back where it left off after the issue leaves Focus or Runway restarts. Tested with Claude; other agents are untested. Takes effect when a terminal starts.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text("The quick terminal always keeps its own conversation. The + button in its header is what starts a new one.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Notifications") {
                Toggle("Play a sound when an agent needs attention", isOn: $soundEnabled)
                    .pointerCursor()
                HStack {
                    Picker("Alert sound", selection: $alertSound) {
                        ForEach(sounds, id: \.self) { Text($0).tag($0) }
                    }
                    .disabled(!soundEnabled)
                    .pointerCursor()
                    Button("Test") { RunwayNotificationManager.playSelectedSound() }
                        .disabled(!soundEnabled)
                        .pointerCursor()
                }

                Toggle("Show a banner even while Runway is in front", isOn: $bannerWhileActive)
                    .pointerCursor()
                Text("Runway always banners while it is in the background. In front, the card's own amber pulse is usually enough, and an agent waiting in another repository shows as an alert in the top-right corner either way.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear {
            agentCommandChoice = ["claude", "codex", "agent"].contains(agentCommand)
                ? agentCommand
                : "custom"
        }
        .onChange(of: agentCommandChoice) { _, choice in
            guard choice != "custom" else { return }
            agentCommand = choice
        }
    }
}
