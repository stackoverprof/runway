import SwiftUI
import AppKit
import ServiceManagement
import Foundation

/// Person profile: login → display name + image data.
struct PersonProfile: Codable, Identifiable {
    var id: String { login }
    let login: String
    var displayName: String
    var imageData: Data?
    
    init(login: String, displayName: String = "", imageData: Data? = nil) {
        self.login = login
        self.displayName = displayName.isEmpty ? login : displayName
        self.imageData = imageData
    }
}

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
    static let agentCommandEnabled = "runway.agentCommandEnabled"
    static let agentCommand  = "runway.agentCommand"
    static let personProfiles = "runway.personProfiles"

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            pollInterval: 45, idleMinutes: 30, officeHours: 6,
            hideBots: true, toastsEnabled: true, soundEnabled: true,
            alertSound: "Glass", confirmQuit: true, initialCommand: "",
            agentCommandEnabled: true, agentCommand: "claude",
            personProfiles: [],
        ])
    }
}

/// Settings window (Runway → Settings…, ⌘,): General + Shortcuts + People tabs.
struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettings()
                .tabItem { Label("General", systemImage: "gearshape") }
            ShortcutSettings()
                .tabItem { Label("Shortcuts", systemImage: "keyboard") }
            PeopleSettings()
                .tabItem { Label("People", systemImage: "person.2.fill") }
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
    @AppStorage(SettingsKey.agentCommandEnabled) private var agentCommandEnabled = true
    @AppStorage(SettingsKey.agentCommand)  private var agentCommand = "claude"
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var cacheCleared = false

    private let sounds = ["Glass", "Ping", "Submarine", "Hero", "Pop", "Funk", "Blow"]
    private let agentCommands = ["claude", "codex", "cursor", "copilot", "gemini"]

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
                Toggle("Run command in each agent", isOn: $agentCommandEnabled)
                HStack {
                    Picker("Command", selection: $agentCommand) {
                        ForEach(agentCommands, id: \.self) { cmd in
                            Text(cmd.capitalized).tag(cmd)
                        }
                    }
                    .disabled(!agentCommandEnabled)
                }
                Text("Runs automatically when an agent opens — new ones (⌘N), every agent when you reopen the app, and the quick terminal. Leave unchecked for a plain shell.")
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

private struct PeopleSettings: View {
    @Bindable var feed = GitHubFeed.shared
    @State private var profiles: [PersonProfile] = []
    @State private var selectedPersonLogin: String?
    @State private var knownLogins: Set<String> = []
    @State private var editingDisplayName = ""

    var body: some View {
        VStack(spacing: 0) {
            peopleList
            
            if let selected = selectedPersonLogin {
                let profile = profiles.first { $0.login == selected } ?? PersonProfile(login: selected)
                Divider()
                editProfilePanel(for: selected, profile: profile)
            }
        }
        .frame(minHeight: 500)
        .onAppear {
            loadProfiles()
            updateKnownLogins()
        }
        .onChange(of: selectedPersonLogin) { _, selected in
            if let selected, let profile = profiles.first(where: { $0.login == selected }) {
                editingDisplayName = profile.displayName
            } else if let selected {
                editingDisplayName = selected
            }
        }
    }

    private var peopleList: some View {
        List(selection: $selectedPersonLogin) {
            if knownLogins.isEmpty {
                Text("People will appear here as they show up in the activity feed.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding()
            } else {
                peopleListRows
            }
        }
        .listStyle(.inset)
    }

    private var peopleListRows: some View {
        ForEach(knownLogins.sorted(), id: \.self) { login in
            peopleRow(login: login)
        }
    }

    private func peopleRow(login: String) -> some View {
        let profile = profiles.first { $0.login == login } ?? PersonProfile(login: login)
        return HStack(spacing: 10) {
            if let imageData = profile.imageData, let nsImage = NSImage(data: imageData) {
                Image(nsImage: nsImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 32, height: 32)
                    .clipShape(Circle())
            } else {
                Circle()
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 32, height: 32)
                    .overlay(Circle().stroke(Color.gray.opacity(0.5), lineWidth: 1))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(profile.displayName)
                    .font(.system(size: 12.5, weight: .semibold))
                Text("@\(login)")
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .contentShape(Rectangle())
        .tag(login)
    }

    private func editProfilePanel(for login: String, profile: PersonProfile) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Edit Profile")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            
            HStack(spacing: 8) {
                if let imageData = profile.imageData, let nsImage = NSImage(data: imageData) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 48, height: 48)
                        .clipShape(Circle())
                } else {
                    Circle()
                        .fill(Color.gray.opacity(0.2))
                        .frame(width: 48, height: 48)
                        .overlay(Circle().stroke(Color.gray.opacity(0.4), lineWidth: 1))
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Button("Upload Image") {
                        let panel = NSOpenPanel()
                        panel.canChooseFiles = true
                        panel.allowsMultipleSelection = false
                        panel.allowedContentTypes = [.image]
                        if panel.runModal() == .OK, let url = panel.url {
                            var updated = profile
                            updated.imageData = try? Data(contentsOf: url)
                            updateProfile(updated)
                        }
                    }
                    .font(.system(size: 11))
                    if profile.imageData != nil {
                        Button("Remove Image", role: .destructive) {
                            var updated = profile
                            updated.imageData = nil
                            updateProfile(updated)
                        }
                        .font(.system(size: 11))
                    }
                }
            }
            
            TextField("Display name", text: $editingDisplayName)
                .font(.system(size: 12))
                .textFieldStyle(.roundedBorder)
                .onChange(of: editingDisplayName) { _, newName in
                    var updated = profile
                    updated.displayName = newName
                    updateProfile(updated)
                }
        }
        .padding()
    }

    private func updateKnownLogins() {
        var logins = Set<String>()
        logins.formUnion(feed.events.map { $0.actor })
        logins.formUnion(feed.presence.map { $0.login })
        knownLogins = logins
    }

    private func loadProfiles() {
        if let data = UserDefaults.standard.data(forKey: SettingsKey.personProfiles),
           let decoded = try? JSONDecoder().decode([PersonProfile].self, from: data) {
            profiles = decoded
        }
    }


    private func updateProfile(_ profile: PersonProfile) {
        if let index = profiles.firstIndex(where: { $0.login == profile.login }) {
            profiles[index] = profile
        } else {
            profiles.append(profile)
        }
        saveProfiles()
    }

    private func saveProfiles() {
        if let encoded = try? JSONEncoder().encode(profiles) {
            UserDefaults.standard.set(encoded, forKey: SettingsKey.personProfiles)
        }
    }
}
