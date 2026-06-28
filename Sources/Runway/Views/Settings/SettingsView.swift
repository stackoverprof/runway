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
    static let initialCommand = "runway.initialCommand"   // run on each new agent
    static let agentCommandEnabled = "runway.agentCommandEnabled"
    static let agentCommand  = "runway.agentCommand"
    static let personProfiles = "runway.personProfiles"

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            pollInterval: 45, idleMinutes: 30, officeHours: 6,
            hideBots: true, soundEnabled: true,
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
