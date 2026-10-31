import SwiftUI

/// UserDefaults keys + their defaults. Consumers read these directly so changes
/// take effect on the next poll/render without extra wiring.
enum SettingsKey {
    static let pollInterval  = "runway.pollInterval"   // seconds
    static let idleMinutes   = "runway.idleMinutes"
    static let officeHours   = "runway.officeHours"
    static let hideBots      = "runway.hideBots"
    static let confirmQuit   = "runway.confirmQuit"
    static let fireThreshold = "runway.fireThreshold"
    static let agentCommandEnabled = "runway.agentCommandEnabled"
    static let agentCommand  = "runway.agentCommand"
    static let terminalFontFamily = "runway.terminalFontFamily"
    static let terminalFontSize = "runway.terminalFontSize"
    static let quickTerminalDirectory = "runway.quickTerminalDirectory"
    static let quickAutoHide = "runway.quickAutoHide"
    static let quickAutoHideSeconds = "runway.quickAutoHideSeconds"
    static let dropRetentionDays = "runway.dropRetentionDays"
    static let personProfiles = "runway.personProfiles"
    static let brandHeaderStyle = "runway.brandHeaderStyle"
    static let brandTitle = "runway.brandTitle"
    static let brandLogoFilename = "runway.brandLogoFilename"
    static let cloneSearchRoot = "runway.cloneSearchRoot"
    static let cloneSearchDepth = "runway.cloneSearchDepth"
    static let pullsTimeframe = "runway.pullsTimeframe"
    static let taglineEnabled = "runway.taglineEnabled"

    // What v3 added. Each of these was a number buried in the code until it
    // turned out to matter: how long a flight you left keeps running, where
    // evidence is written, whether landing without it is questioned.
    static let walkthroughRoot = WalkthroughSlides.key
    static let walkthroughSlides = "runway.walkthroughSlides"
    static let askBeforeLandingWithoutEvidence = "runway.askBeforeLandingWithoutEvidence"
    static let seatIdleMinutes = "runway.seatIdleMinutes"
    static let seatsKeptAlive = "runway.seatsKeptAlive"
    static let pilotTerminalPadding = "runway.pilotTerminalPadding"

    /// The command every agent starts with. Runway flies Claude, so that is
    /// the default; turning it off leaves a plain shell.
    static var configuredAgentCommand: String {
        let enabled = UserDefaults.standard.object(forKey: agentCommandEnabled) as? Bool ?? true
        guard enabled else { return "" }
        let command = (UserDefaults.standard.string(forKey: agentCommand) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return command.isEmpty ? "claude" : command
    }

    /// Seconds the ATC panel waits before hiding itself.
    static func quickAutoHideDelay(in defaults: UserDefaults = .standard) -> TimeInterval {
        let saved = defaults.integer(forKey: quickAutoHideSeconds)
        return TimeInterval(min(max(saved == 0 ? 3 : saved, 1), 60))
    }

    static func quickAutoHideEnabled(in defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: quickAutoHide) == nil
            ? true
            : defaults.bool(forKey: quickAutoHide)
    }

    /// How long a dropped image is kept before Runway prunes it. Zero days
    /// means keep them.
    static func dropRetention(in defaults: UserDefaults = .standard) -> TimeInterval? {
        guard defaults.object(forKey: dropRetentionDays) != nil else { return 7 * 86_400 }
        let days = defaults.integer(forKey: dropRetentionDays)
        guard days > 0 else { return nil }
        return TimeInterval(min(days, 365)) * 86_400
    }

    // Readers for the settings that shape behaviour elsewhere. Each takes the
    // store, so a test can hand in its own domain instead of racing the shared
    // one, and each holds a sane value when the preference is unset or has been
    // hand-edited to nonsense.

    /// Where Runway looks for cloned repositories, and how deep it descends.
    static func cloneSearch(in defaults: UserDefaults = .standard) -> (root: String, depth: Int) {
        let root = (defaults.string(forKey: cloneSearchRoot) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let depth = defaults.integer(forKey: cloneSearchDepth)
        return (
            root.isEmpty ? NSHomeDirectory() : (root as NSString).expandingTildeInPath,
            min(max(depth == 0 ? 6 : depth, 1), 12)
        )
    }

    static func configuredPullsTimeframe(in defaults: UserDefaults = .standard) -> PRTimeframe {
        let stored = defaults.string(forKey: pullsTimeframe) ?? ""
        // Keep existing installations on the same selection after renaming 1d.
        if stored == "1d" { return .oneDay }
        return PRTimeframe(rawValue: stored) ?? .monthToDate
    }

    static func registerDefaults() {
        let defaults = UserDefaults.standard
        defaults.register(defaults: [
            pollInterval: 45, idleMinutes: 30, officeHours: 6,
            hideBots: true, confirmQuit: true, fireThreshold: 5,
            agentCommandEnabled: true, agentCommand: "claude",
            terminalFontFamily: TerminalFont.defaultFamily,
            terminalFontSize: TerminalFont.defaultSize,
            quickTerminalDirectory: "",
            quickAutoHide: true,
            quickAutoHideSeconds: 3,
            dropRetentionDays: 7,
            personProfiles: [],
            brandHeaderStyle: "text",
            brandTitle: "Runway V3",
            brandLogoFilename: "",
            cloneSearchRoot: "",
            cloneSearchDepth: 6,
            pullsTimeframe: PRTimeframe.monthToDate.rawValue,
            taglineEnabled: true,
            walkthroughRoot: "",
            walkthroughSlides: 3,
            askBeforeLandingWithoutEvidence: true,
            seatIdleMinutes: 15,
            seatsKeptAlive: 12,
            pilotTerminalPadding: 9,
        ])

    }
}

/// Settings window (Runway → Settings…, ⌘,).
///
/// One tab per thing being configured rather than one long General list, so a
/// setting is found by what it affects: the feed, the pane's own identity, the
/// people in it.
struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettings()
                .tabItem { Label("General", systemImage: "gearshape") }
            FeedSettings()
                .tabItem { Label("Feed", systemImage: "dot.radiowaves.up.forward") }
            TerminalSettings()
                .tabItem { Label("Terminal", systemImage: "terminal") }
            FlightSettings()
                .tabItem { Label("Flights", systemImage: "airplane") }
            HouseRulesSettings()
                .tabItem { Label("House rules", systemImage: "list.bullet.clipboard") }
            AppearanceSettings()
                .tabItem { Label("Appearance", systemImage: "paintbrush") }
            ShortcutSettings()
                .tabItem { Label("Shortcuts", systemImage: "keyboard") }
            PeopleSettings()
                .tabItem { Label("People", systemImage: "person.2.fill") }
        }
        .frame(width: 540, height: 500)
    }
}
