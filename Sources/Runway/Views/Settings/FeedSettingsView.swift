import SwiftUI
import AppKit

/// Everything about what the left pane pulls from GitHub and how often.
struct FeedSettings: View {
    @AppStorage(SettingsKey.pollInterval)  private var pollInterval = 45
    @AppStorage(SettingsKey.idleMinutes)   private var idleMinutes = 30
    @AppStorage(SettingsKey.officeHours)   private var officeHours = 6
    @AppStorage(SettingsKey.hideBots)      private var hideBots = true
    @AppStorage(SettingsKey.fireThreshold) private var fireThreshold = 5
    @AppStorage(SettingsKey.taglineEnabled) private var taglineEnabled = true
    @AppStorage(SettingsKey.pullsTimeframe) private var pullsTimeframe = PRTimeframe.monthToDate.rawValue
    @AppStorage(SettingsKey.cloneSearchRoot) private var cloneSearchRoot = ""
    @AppStorage(SettingsKey.cloneSearchDepth) private var cloneSearchDepth = 6

    var body: some View {
        Form {
            Section("Activity feed") {
                Picker("Refresh every", selection: $pollInterval) {
                    Text("15 seconds").tag(15)
                    Text("30 seconds").tag(30)
                    Text("45 seconds").tag(45)
                    Text("1 minute").tag(60)
                    Text("2 minutes").tag(120)
                }
                .pointerCursor()
                Stepper("Active within: \(idleMinutes) min", value: $idleMinutes, in: 5...120, step: 5)
                    .pointerCursor()
                Stepper("On fire threshold: \(fireThreshold) events", value: $fireThreshold, in: 2...20)
                    .pointerCursor()
                Picker("Show people active in the last", selection: $officeHours) {
                    Text("3 hours").tag(3)
                    Text("6 hours").tag(6)
                    Text("12 hours").tag(12)
                    Text("24 hours").tag(24)
                }
                .pointerCursor()
                Toggle("Hide bot accounts", isOn: $hideBots)
                    .pointerCursor()

                Text("Feeds, Runway, and Pulls share this clock, and all three refresh when the window becomes active. Polling pauses while Runway is inactive.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Toggle("Rotate the tagline on refresh", isOn: $taglineEnabled)
                    .pointerCursor()
                Text("The line under the header retypes itself when the feed refreshes, so a refresh that found nothing still shows. Turn it off for a still header.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Pull requests") {
                Picker("Pulls opens on", selection: $pullsTimeframe) {
                    ForEach(PRTimeframe.allCases) { timeframe in
                        Text(timeframe.rawValue).tag(timeframe.rawValue)
                    }
                }
                .pointerCursor()
                Text("The timeframe the Pulls tab starts on every launch.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Repositories") {
                HStack(spacing: 8) {
                    TextField(
                        "Search in",
                        text: $cloneSearchRoot,
                        prompt: Text("Home folder")
                    )
                    Button("Choose\u{2026}") { chooseCloneRoot() }
                        .pointerCursor()
                }
                Stepper("Search depth: \(cloneSearchDepth)", value: $cloneSearchDepth, in: 1...12)
                    .pointerCursor()

                if let cloneRootWarning {
                    Text(cloneRootWarning)
                        .font(.caption)
                        .foregroundStyle(.orange)
                }

                if !cloneSearchRoot.isEmpty {
                    Button("Restore Default", role: .destructive) { cloneSearchRoot = "" }
                        .pointerCursor()
                }

                Text("Where the repository picker looks for cloned GitHub repositories, and how many folders deep it descends. A narrower root scans faster and keeps stray checkouts out of the list.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    /// The scan silently falls back to the home folder, so only a typed path
    /// that is not a folder is worth a word.
    private var cloneRootWarning: String? {
        let trimmed = cloneSearchRoot.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, QuickTerminalDirectory.resolved(trimmed) == nil else {
            return nil
        }
        return "\(trimmed) is not a folder on this Mac, so Runway searches your home folder."
    }

    private func chooseCloneRoot() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Choose the folder Runway searches for cloned repositories"
        panel.prompt = "Choose Folder"
        if let current = QuickTerminalDirectory.resolved(cloneSearchRoot) {
            panel.directoryURL = URL(fileURLWithPath: current)
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        cloneSearchRoot = url.path
    }
}
