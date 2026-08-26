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
    @State private var agentCommandChoice = "claude"

    private let sounds = ["Glass", "Ping", "Submarine", "Hero", "Pop", "Funk", "Blow"]

    var body: some View {
        Form {
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
