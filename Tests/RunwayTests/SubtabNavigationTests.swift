import Foundation
import Testing
@testable import Runway

@Suite("Subtab navigation")
struct SubtabNavigationTests {
    @Test("Stepping wraps at both ends")
    func wrapsBothWays() {
        #expect(SubtabNavigation.index(from: 0, by: -1, count: 5) == 4)
        #expect(SubtabNavigation.index(from: 4, by: 1, count: 5) == 0)
        #expect(SubtabNavigation.index(from: 1, by: 1, count: 5) == 2)
    }

    @Test("A tab with nothing to step through stays put")
    func singleOption() {
        #expect(SubtabNavigation.index(from: 0, by: 1, count: 1) == nil)
        #expect(SubtabNavigation.index(from: 0, by: 1, count: 0) == nil)
    }

    @Test("Pulls opens on the month in progress")
    func pullsDefaultsToMonthToDate() {
        #expect(PRTimeframe.initial == .monthToDate)

        var components = DateComponents()
        components.year = 2026
        components.month = 8
        components.day = 24
        components.hour = 21
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Jakarta") ?? .gmt
        let now = calendar.date(from: components)!

        let start = PRTimeframe.monthToDate.startDate(now: now, calendar: calendar)
        let parts = calendar.dateComponents([.year, .month, .day], from: start)
        #expect(parts.year == 2026)
        #expect(parts.month == 8)
        #expect(parts.day == 1)
    }
}
