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
        #expect(SettingsKey.cloneSearch(in: defaults).root == NSHomeDirectory())
        #expect(SettingsKey.cloneSearch(in: defaults).depth == 6)
        #expect(SettingsKey.configuredPullsTimeframe(in: defaults) == .monthToDate)
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

    @Test("An unknown stored timeframe falls back instead of breaking")
    func unknownTimeframeFallsBack() {
        let defaults = store("fallback")
        defaults.set("nonsense", forKey: SettingsKey.pullsTimeframe)
        #expect(SettingsKey.configuredPullsTimeframe(in: defaults) == .monthToDate)
        defaults.set("1d", forKey: SettingsKey.pullsTimeframe)
        #expect(SettingsKey.configuredPullsTimeframe(in: defaults) == .oneDay)
    }
}
