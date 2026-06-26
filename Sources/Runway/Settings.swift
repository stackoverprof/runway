import SwiftUI
import AppKit
import ServiceManagement

/// UserDefaults keys + their defaults. Consumers read these directly so changes
/// take effect on the next poll/render without extra wiring.
enum SettingsKey {
    static let pollInterval  = "runway.pollInterval"   // seconds
    static let idleMinutes   = "runway.idleMinutes"
    static let officeHours   = "runway.officeHours"
    static let hideBots      = "runway.hideBots"
    static let toastsEnabled = "runway.toastsEnabled"
    static let soundEnabled  = "runway.soundEnabled"
    static let alertSound    = "runway.alertSound"
    static let confirmQuit   = "runway.confirmQuit"
    static let initialCommand = "runway.initialCommand"   // run on each new agent

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            pollInterval: 45, idleMinutes: 30, officeHours: 6,
            hideBots: true, toastsEnabled: true, soundEnabled: true,
            alertSound: "Glass", confirmQuit: true, initialCommand: "",
        ])
    }
}

/// Settings window (Runway → Settings…, ⌘,): General + Shortcuts tabs.
struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettings()
                .tabItem { Label("General", systemImage: "gearshape") }
            ShortcutSettings()
                .tabItem { Label("Shortcuts", systemImage: "keyboard") }
        }
        .frame(width: 460, height: 500)
    }
}

private struct GeneralSettings: View {
    @AppStorage(SettingsKey.pollInterval)  private var pollInterval = 45
    @AppStorage(SettingsKey.idleMinutes)   private var idleMinutes = 30
    @AppStorage(SettingsKey.officeHours)   private var officeHours = 6
    @AppStorage(SettingsKey.hideBots)      private var hideBots = true
    @AppStorage(SettingsKey.toastsEnabled) private var toastsEnabled = true
    @AppStorage(SettingsKey.soundEnabled)  private var soundEnabled = true
    @AppStorage(SettingsKey.alertSound)    private var alertSound = "Glass"
    @AppStorage(SettingsKey.confirmQuit)   private var confirmQuit = true
    @AppStorage(SettingsKey.initialCommand) private var initialCommand = ""
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var cacheCleared = false

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
                Stepper("Active within: \(idleMinutes) min", value: $idleMinutes, in: 5...120, step: 5)
                Picker("Show people active in the last", selection: $officeHours) {
                    Text("3 hours").tag(3)
                    Text("6 hours").tag(6)
                    Text("12 hours").tag(12)
                    Text("24 hours").tag(24)
                }
                Toggle("Hide bot accounts", isOn: $hideBots)
            }

            Section("Notifications") {
                Toggle("Show toasts", isOn: $toastsEnabled)
                Toggle("Play a sound when an agent needs attention", isOn: $soundEnabled)
                HStack {
                    Picker("Alert sound", selection: $alertSound) {
                        ForEach(sounds, id: \.self) { Text($0).tag($0) }
                    }
                    .disabled(!soundEnabled)
                    Button("Test") { ToastCenter.playSelectedSound() }
                        .disabled(!soundEnabled)
                }
            }

            Section("Agents") {
                TextField("Run in each agent", text: $initialCommand, prompt: Text("e.g. claude"))
                    .autocorrectionDisabled()
                Text("Runs automatically when an agent opens — new ones (⌘N), every agent when you reopen the app, and the quick terminal. Leave blank for a plain shell.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("General") {
                Toggle("Confirm before quitting", isOn: $confirmQuit)
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, on in
                        try? on ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister()
                    }
                HStack {
                    Button("Clear activity-feed cache") {
                        GitHubFeed.clearCache()
                        cacheCleared = true
                    }
                    if cacheCleared {
                        Text("Cleared").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}
