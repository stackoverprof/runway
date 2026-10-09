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
    static let issueAgentSessionsEnabled = "runway.issueAgentSessionsEnabled"
    static let personProfiles = "runway.personProfiles"
    static let brandHeaderStyle = "runway.brandHeaderStyle"
    static let brandTitle = "runway.brandTitle"
    static let brandLogoFilename = "runway.brandLogoFilename"
    static let focusBoardCollapsed = "runway.focusBoardCollapsed"
    static let focusVisibleCount = "runway.focusVisibleCount"
    /// Most issues Focus holds. Zero means unlimited.
    static let focusLimit = "runway.focusLimit"
    static let terminalFontFamily = "runway.terminalFontFamily"
    static let terminalFontSize = "runway.terminalFontSize"
    static let quickTerminalDirectory = "runway.quickTerminalDirectory"
    static let quickAutoHide = "runway.quickAutoHide"
    static let quickAutoHideSeconds = "runway.quickAutoHideSeconds"
    static let cloneSearchRoot = "runway.cloneSearchRoot"
    static let cloneSearchDepth = "runway.cloneSearchDepth"
    static let pullsTimeframe = "runway.pullsTimeframe"
    static let defaultLayoutAxis = "runway.defaultLayoutAxis"
    static let bannerWhileActive = "runway.bannerWhileActive"
    static let dropRetentionDays = "runway.dropRetentionDays"
    static let taglineEnabled = "runway.taglineEnabled"

    static var configuredAgentCommand: String {
        guard UserDefaults.standard.bool(forKey: agentCommandEnabled) else { return "" }
        return (UserDefaults.standard.string(forKey: agentCommand) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // Readers for the settings that shape behaviour elsewhere. Each takes the
    // store, so a test can hand in its own domain instead of racing the shared
    // one, and each holds a sane value when the preference is unset or has been
    // hand-edited to nonsense.

    /// Seconds the quick terminal waits before hiding itself.
    static func quickAutoHideDelay(in defaults: UserDefaults = .standard) -> TimeInterval {
        let saved = defaults.integer(forKey: quickAutoHideSeconds)
        return TimeInterval(min(max(saved == 0 ? 3 : saved, 1), 60))
    }

    static func quickAutoHideEnabled(in defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: quickAutoHide) == nil
            ? true
            : defaults.bool(forKey: quickAutoHide)
    }

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

    static func configuredLayoutAxis(in defaults: UserDefaults = .standard) -> TerminalLayoutAxis {
        TerminalLayoutAxis(rawValue: defaults.string(forKey: defaultLayoutAxis) ?? "") ?? .vertical
    }

    /// How long a dropped image is kept before Runway prunes it. Zero days
    /// means keep them.
    static func dropRetention(in defaults: UserDefaults = .standard) -> TimeInterval? {
        guard defaults.object(forKey: dropRetentionDays) != nil else { return 7 * 86_400 }
        let days = defaults.integer(forKey: dropRetentionDays)
        guard days > 0 else { return nil }
        return TimeInterval(min(days, 365)) * 86_400
    }

    /// How many Focus cards, and so terminals, the window shows at once.
    static func configuredFocusVisibleCount(in defaults: UserDefaults = .standard) -> Int {
        guard defaults.object(forKey: focusVisibleCount) != nil else {
            return FocusReel.defaultVisibleCount
        }
        let range = FocusReel.visibleCountRange
        return min(max(defaults.integer(forKey: focusVisibleCount), range.lowerBound), range.upperBound)
    }

    /// The most issues Focus takes, or nil for unlimited.
    static func configuredFocusLimit(in defaults: UserDefaults = .standard) -> Int? {
        guard defaults.object(forKey: focusLimit) != nil else { return FocusReel.defaultLimit }
        let saved = defaults.integer(forKey: focusLimit)
        guard saved > 0 else { return nil }
        return min(saved, FocusReel.limitRange.upperBound)
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
            issueAgentSessionsEnabled: true,
            personProfiles: [],
            brandHeaderStyle: "text",
            brandTitle: "Activity",
            brandLogoFilename: "",
            focusBoardCollapsed: false,
            focusVisibleCount: FocusReel.defaultVisibleCount,
            focusLimit: FocusReel.defaultLimit,
            terminalFontFamily: TerminalFont.defaultFamily,
            terminalFontSize: TerminalFont.defaultSize,
            quickTerminalDirectory: "",
            quickAutoHide: true,
            quickAutoHideSeconds: 3,
            cloneSearchRoot: "",
            cloneSearchDepth: 6,
            pullsTimeframe: PRTimeframe.monthToDate.rawValue,
            defaultLayoutAxis: TerminalLayoutAxis.vertical.rawValue,
            bannerWhileActive: false,
            dropRetentionDays: 7,
            taglineEnabled: true,
        ])

        // Older builds used `initialCommand` at runtime while exposing different
        // keys in Settings. Carry an existing command forward exactly once.
        if !hasNewAgentPreference, !legacyCommand.isEmpty {
            defaults.set(true, forKey: agentCommandEnabled)
            defaults.set(legacyCommand, forKey: agentCommand)
        }
    }
}

/// Settings window (Runway → Settings…, ⌘,).
///
/// One tab per thing being configured rather than one long General list, so a
/// setting is found by what it affects: the feed, the terminals, the agents in
/// them, the pane's own identity.
struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettings()
                .tabItem { Label("General", systemImage: "gearshape") }
            FeedSettings()
                .tabItem { Label("Feed", systemImage: "dot.radiowaves.up.forward") }
            TerminalSettings()
                .tabItem { Label("Terminal", systemImage: "terminal") }
            AgentSettings()
                .tabItem { Label("Agents", systemImage: "sparkles") }
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
