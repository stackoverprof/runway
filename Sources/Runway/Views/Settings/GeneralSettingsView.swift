import SwiftUI
import ServiceManagement

/// What is left once the feed, terminals, agents, and branding have their own
/// tabs: how Runway itself starts and stops, and the stored state it can reset.
struct GeneralSettings: View {
    @AppStorage(SettingsKey.confirmQuit) private var confirmQuit = true
    @AppStorage(SettingsKey.agentModel) private var agentModel = ""
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var cacheCleared = false
    @State private var restartingSessions = false
    @State private var restartMessage: String?

    var body: some View {
        Form {
            Section("Startup") {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, on in
                        try? on ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister()
                    }
                Toggle("Confirm before quitting", isOn: $confirmQuit)
            }

            Section("Agents") {
                Picker("Claude model", selection: $agentModel) {
                    Text("Claude default").tag("")
                    Text("Sonnet").tag("sonnet")
                    Text("Opus").tag("opus")
                    Text("Haiku").tag("haiku")
                }

                Button(restartButtonTitle) {
                    restartingSessions = true
                    restartMessage = nil
                    Task { @MainActor in
                        let count = await AgentSessionRestarter.restartAll(on: agentModel)
                        restartMessage = "Restarted \(count) Claude session\(count == 1 ? "" : "s")."
                        restartingSessions = false
                    }
                }
                .disabled(restartingSessions)
                if restartingSessions {
                    Text("Stopping and resuming the open Claude sessions…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if let restartMessage {
                    Text(restartMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text("Busy sessions are interrupted, then reopened on the same conversation with the selected model.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Stored data") {
                HStack {
                    Button("Clear activity-feed cache") {
                        GitHubFeed.clearCache()
                        cacheCleared = true
                    }
                    if cacheCleared {
                        Text("Cleared").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Text("Drops every repository's cached feed. The next refresh refetches it from GitHub.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

            }
        }
        .formStyle(.grouped)
    }

    private var restartButtonTitle: String {
        agentModel.isEmpty
            ? "Restart all sessions on Claude default"
            : "Restart all sessions on \(agentModel.capitalized)"
    }
}
