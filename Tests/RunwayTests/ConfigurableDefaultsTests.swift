import Foundation
import Testing
@testable import Runway

/// The readers behind the new Settings controls. Each test owns its own defaults
/// domain, so none of them can race another or leak into the shared store.
@Suite("Configurable defaults")
struct ConfigurableDefaultsTests {
    private func store(_ name: String) -> UserDefaults {
        let suite = "runway.tests.settings.\(name)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    @Test("Unset preferences keep every previous hardcoded default")
    func unsetKeepsOldBehaviour() {
        let defaults = store("unset")
        #expect(SettingsKey.quickAutoHideDelay(in: defaults) == 3)
        #expect(SettingsKey.quickAutoHideEnabled(in: defaults))
        #expect(SettingsKey.cloneSearch(in: defaults).root == NSHomeDirectory())
        #expect(SettingsKey.cloneSearch(in: defaults).depth == 6)
        #expect(SettingsKey.configuredPullsTimeframe(in: defaults) == .monthToDate)
        #expect(SettingsKey.configuredLayoutAxis(in: defaults) == .vertical)
        #expect(SettingsKey.dropRetention(in: defaults) == TimeInterval(7 * 86_400))
    }

    @Test("A hand-edited quick-terminal delay is clamped, never zero or forever")
    func autoHideDelayIsClamped() {
        let defaults = store("delay")
        defaults.set(-5, forKey: SettingsKey.quickAutoHideSeconds)
        #expect(SettingsKey.quickAutoHideDelay(in: defaults) == 1)
        defaults.set(9_999, forKey: SettingsKey.quickAutoHideSeconds)
        #expect(SettingsKey.quickAutoHideDelay(in: defaults) == 60)
        defaults.set(12, forKey: SettingsKey.quickAutoHideSeconds)
        #expect(SettingsKey.quickAutoHideDelay(in: defaults) == 12)
    }

    @Test("Auto-hide can be switched off")
    func autoHideCanBeDisabled() {
        let defaults = store("autohide")
        defaults.set(false, forKey: SettingsKey.quickAutoHide)
        #expect(!SettingsKey.quickAutoHideEnabled(in: defaults))
    }

    @Test("A clone root is tilde-expanded and its depth stays in range")
    func cloneSearchExpandsAndClamps() {
        let defaults = store("clones")
        defaults.set("  ~/Developer ", forKey: SettingsKey.cloneSearchRoot)
        defaults.set(99, forKey: SettingsKey.cloneSearchDepth)
        let search = SettingsKey.cloneSearch(in: defaults)
        #expect(search.root == "\(NSHomeDirectory())/Developer")
        #expect(search.depth == 12)
    }

    @Test("An unknown stored timeframe or axis falls back instead of breaking")
    func enumsFallBack() {
        let defaults = store("enums")
        defaults.set("nonsense", forKey: SettingsKey.pullsTimeframe)
        defaults.set("sideways", forKey: SettingsKey.defaultLayoutAxis)
        #expect(SettingsKey.configuredPullsTimeframe(in: defaults) == .monthToDate)
        #expect(SettingsKey.configuredLayoutAxis(in: defaults) == .vertical)

        defaults.set(PRTimeframe.sevenDays.rawValue, forKey: SettingsKey.pullsTimeframe)
        defaults.set(TerminalLayoutAxis.horizontal.rawValue, forKey: SettingsKey.defaultLayoutAxis)
        #expect(SettingsKey.configuredPullsTimeframe(in: defaults) == .sevenDays)
        #expect(SettingsKey.configuredLayoutAxis(in: defaults) == .horizontal)
    }

    @Test("Zero days keeps dropped images, and a window is capped at a year")
    func dropRetentionWindow() {
        let defaults = store("drops")
        defaults.set(0, forKey: SettingsKey.dropRetentionDays)
        #expect(SettingsKey.dropRetention(in: defaults) == nil)
        defaults.set(3, forKey: SettingsKey.dropRetentionDays)
        #expect(SettingsKey.dropRetention(in: defaults) == TimeInterval(3 * 86_400))
        defaults.set(10_000, forKey: SettingsKey.dropRetentionDays)
        #expect(SettingsKey.dropRetention(in: defaults) == TimeInterval(365 * 86_400))
    }
}
