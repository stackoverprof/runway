import Foundation
import Testing
@testable import Runway

@Suite("runway:// links")
struct RunwayURLCommandTests {
    private func tabs(_ link: String) -> [FeedTab]? {
        RunwayURLCommand.refreshTabs(in: URL(string: link)!)
    }

    @Test("A refresh names one tab")
    func oneTab() {
        #expect(tabs("runway://refresh?tab=feeds") == [.feeds])
        #expect(tabs("runway://refresh?tab=pulls") == [.pullRequests])
    }

    @Test("A bare refresh, or tab=all, refreshes every tab")
    func allTabs() {
        #expect(tabs("runway://refresh") == FeedTab.allCases)
        #expect(tabs("runway://refresh?tab=all") == FeedTab.allCases)
    }

    @Test("Anything else is ignored")
    func ignored() {
        #expect(tabs("runway://refresh?tab=nope") == nil)
        #expect(tabs("runway://refresh?tab=runway") == nil)
        #expect(tabs("runway://open?tab=feeds") == nil)
        #expect(tabs("https://refresh?tab=feeds") == nil)
    }
}
