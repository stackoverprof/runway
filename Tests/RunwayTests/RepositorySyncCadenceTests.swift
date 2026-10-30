import Foundation
import Testing
@testable import Runway

@Suite("Repository sync cadence")
struct RepositorySyncCadenceTests {
    @Test("Both sources refresh on the same tick, whichever tab is in front")
    func allSourcesShareOneTick() {
        for tab in FeedTab.allCases {
            let ages = RepositorySyncCadence.ages(for: tab, tick: 45)
            #expect(ages.feed <= 90)
            #expect(ages.pulls <= 90)
        }
    }

    @Test("The tab in front leads, the one behind follows within one tick")
    func visibleTabLeads() {
        let onPulls = RepositorySyncCadence.ages(for: .pullRequests, tick: 45)
        #expect(onPulls.pulls == 45)
        #expect(onPulls.feed == 90)

        let onFeeds = RepositorySyncCadence.ages(for: .feeds, tick: 45)
        #expect(onFeeds.feed == 45)
        #expect(onFeeds.pulls == 90)
    }

    @Test("Returning to the window refreshes everything, not only the front tab")
    func activationRefreshesBackgroundTabs() {
        let ages = RepositorySyncCadence.ages(for: .feeds, tick: 15)
        #expect(ages.feed == 15)
        #expect(ages.pulls == 30)
    }
}
