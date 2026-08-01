import SwiftUI
import ServiceManagement
import AppKit
import UniformTypeIdentifiers

struct GeneralSettings: View {
    @AppStorage(SettingsKey.pollInterval)  private var pollInterval = 45
    @AppStorage(SettingsKey.idleMinutes)   private var idleMinutes = 30
    @AppStorage(SettingsKey.officeHours)   private var officeHours = 6
    @AppStorage(SettingsKey.hideBots)      private var hideBots = true
    @AppStorage(SettingsKey.fireThreshold)  private var fireThreshold = 5
    @AppStorage(SettingsKey.soundEnabled)  private var soundEnabled = true
    @AppStorage(SettingsKey.alertSound)    private var alertSound = "Glass"
    @AppStorage(SettingsKey.confirmQuit)   private var confirmQuit = true
    @AppStorage(SettingsKey.agentCommandEnabled) private var agentCommandEnabled = false
    @AppStorage(SettingsKey.agentCommand)  private var agentCommand = "claude"
    @AppStorage(SettingsKey.brandHeaderStyle) private var brandHeaderStyle = "text"
    @AppStorage(SettingsKey.brandTitle) private var brandTitle = "Activity"
    @AppStorage(SettingsKey.brandLogoFilename) private var brandLogoFilename = ""
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var cacheCleared = false
    @State private var issueOrderReset = false
    @State private var brandingError: String?
    @State private var agentCommandChoice = "claude"

    private let sounds = ["Glass", "Ping", "Submarine", "Hero", "Pop", "Funk", "Blow"]
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
            }

            Section("Branding") {
                Picker("Header", selection: $brandHeaderStyle) {
                    Text("Text").tag("text")
                    Text("Image").tag("image")
                }
                .pickerStyle(.segmented)
                .pointerCursor()

                if brandHeaderStyle == "text" {
                    TextField("Title", text: $brandTitle)
                } else {
                    HStack(spacing: 8) {
                        Button(brandLogoFilename.isEmpty ? "Choose Logo…" : "Change Logo…") {
                            chooseLogo()
                        }
                        .pointerCursor()
                        if !brandLogoFilename.isEmpty {
                            Button("Remove Logo", role: .destructive) {
                                BrandingManager.removeLogo(named: brandLogoFilename)
                                brandLogoFilename = ""
                                brandingError = nil
                            }
                            .pointerCursor()
                        }
                    }
                }

                HStack(spacing: 12) {
                    Text("Preview")
                        .foregroundStyle(.secondary)
                    Spacer()
                    brandingPreview
                }

                if brandHeaderStyle != "text" || brandTitle != "Activity" || !brandLogoFilename.isEmpty {
                    Button("Restore Default", role: .destructive) {
                        BrandingManager.removeLogo(named: brandLogoFilename)
                        brandLogoFilename = ""
                        brandTitle = "Activity"
                        brandHeaderStyle = "text"
                        brandingError = nil
                    }
                    .pointerCursor()
                }

                Text("Replaces the Activity title in the left pane with custom text or any image format macOS can open, including SVG, PNG, and JPEG.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let brandingError {
                    Text(brandingError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
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
            }

            Section("Agents") {
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

            Section("Issue boards") {
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

            Section("General") {
                Toggle("Confirm before quitting", isOn: $confirmQuit)
                    .pointerCursor()
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .pointerCursor()
                    .onChange(of: launchAtLogin) { _, on in
                        try? on ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister()
                    }
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

    @ViewBuilder
    private var brandingPreview: some View {
        if brandHeaderStyle == "image",
           let image = BrandingManager.image(named: brandLogoFilename) {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .frame(width: 180, height: 42)
        } else {
            Text(resolvedBrandTitle)
                .font(.system(size: 27, weight: .bold))
                .lineLimit(1)
                .frame(maxWidth: 180, minHeight: 42, alignment: .trailing)
        }
    }

    private var resolvedBrandTitle: String {
        let title = brandTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? "Activity" : title
    }

    private func chooseLogo() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.image]
        panel.message = "Choose a logo for the Activity pane"
        panel.prompt = "Choose Logo"
        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            brandLogoFilename = try BrandingManager.importLogo(
                from: url,
                replacing: brandLogoFilename
            )
            brandHeaderStyle = "image"
            brandingError = nil
        } catch {
            brandingError = error.localizedDescription
        }
    }

}
