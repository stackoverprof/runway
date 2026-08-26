import SwiftUI
import ServiceManagement

/// What is left once the feed, terminals, agents, and branding have their own
/// tabs: how Runway itself starts and stops, and the stored state it can reset.
struct GeneralSettings: View {
    @AppStorage(SettingsKey.confirmQuit) private var confirmQuit = true
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var cacheCleared = false
    @State private var issueOrderReset = false

    var body: some View {
        Form {
            Section("Startup") {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .pointerCursor()
                    .onChange(of: launchAtLogin) { _, on in
                        try? on ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister()
                    }
                Toggle("Confirm before quitting", isOn: $confirmQuit)
                    .pointerCursor()
            }

            Section("Stored data") {
                HStack {
                    Button("Clear activity-feed cache") {
                        GitHubFeed.clearCache()
                        cacheCleared = true
                    }
                    .pointerCursor()
                    if cacheCleared {
                        Text("Cleared").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Text("Drops every repository's cached feed. The next refresh refetches it from GitHub.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack {
                    Button("Reset Open & Closed Order", role: .destructive) {
                        AssignedIssues.resetSavedBacklogOrder()
                        issueOrderReset = true
                    }
                    .pointerCursor()
                    if issueOrderReset {
                        Text("Reset")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Text("Restores the default GitHub ordering for Open and Closed issues. Focus membership and Focus order are not changed.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
