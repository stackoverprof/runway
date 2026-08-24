import Foundation

/// Freshness targets for one sync tick.
struct RepositorySyncAges: Equatable {
    let feed: TimeInterval
    let issues: TimeInterval
    let pulls: TimeInterval
}

/// How stale each source is allowed to be when the left pane syncs.
///
/// All three refresh on the same tick, so the feed, the Focus board and the pull
/// requests describe the same moment. The tab in front gets the tick itself; the
/// two behind it are allowed to be twice as old, which keeps a background tab
/// from tripling the traffic while still holding it within a tick of the truth.
enum RepositorySyncCadence {
    static let backgroundMultiplier: TimeInterval = 2

    static func ages(for tab: FeedTab, tick: TimeInterval) -> RepositorySyncAges {
        let background = tick * backgroundMultiplier
        return RepositorySyncAges(
            feed: tab == .feeds ? tick : background,
            issues: tab == .runway ? tick : background,
            pulls: tab == .pullRequests ? tick : background
        )
    }
}
