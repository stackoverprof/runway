import SwiftUI

/// UserDefaults keys + their defaults. Consumers read these directly so changes
/// take effect on the next poll/render without extra wiring.
enum SettingsKey {
    static let pollInterval  = "runway.pollInterval"   // seconds
    static let idleMinutes   = "runway.idleMinutes"
    static let officeHours   = "runway.officeHours"
    static let hideBots      = "runway.hideBots"
    static let soundEnabled  = "runway.soundEnabled"
    static let alertSound    = "runway.alertSound"
    static let confirmQuit   = "runway.confirmQuit"
    static let fireThreshold = "runway.fireThreshold"
    static let initialCommand = "runway.initialCommand"   // run on each new agent
    static let agentCommandEnabled = "runway.agentCommandEnabled"
    static let agentCommand  = "runway.agentCommand"
    static let personProfiles = "runway.personProfiles"

    static var configuredAgentCommand: String {
        guard UserDefaults.standard.bool(forKey: agentCommandEnabled) else { return "" }
        return (UserDefaults.standard.string(forKey: agentCommand) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func registerDefaults() {
        let defaults = UserDefaults.standard
        let legacyCommand = (defaults.string(forKey: initialCommand) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let hasNewAgentPreference = defaults.object(forKey: agentCommandEnabled) != nil
            || defaults.object(forKey: agentCommand) != nil

        defaults.register(defaults: [
            pollInterval: 45, idleMinutes: 30, officeHours: 6,
            hideBots: true, soundEnabled: true,
            alertSound: "Glass", confirmQuit: true, fireThreshold: 5, initialCommand: "",
            // Preserve the app's historical effective behavior: a plain shell
            // until the user explicitly enables an agent command.
            agentCommandEnabled: false, agentCommand: "claude",
            personProfiles: [],
        ])

        // Older builds used `initialCommand` at runtime while exposing different
        // keys in Settings. Carry an existing command forward exactly once.
        if !hasNewAgentPreference, !legacyCommand.isEmpty {
            defaults.set(true, forKey: agentCommandEnabled)
            defaults.set(legacyCommand, forKey: agentCommand)
        }
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
