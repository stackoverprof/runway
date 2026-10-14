import AppKit
import Foundation

/// `runway://` links, for scripts and agents that change something Runway
/// shows and want it on screen now rather than on the next sync tick.
///
///     open -g "runway://refresh?tab=runway"   # the Runway tab's issues
///     open -g "runway://refresh?tab=feeds"
///     open -g "runway://refresh?tab=pulls"
///     open -g "runway://refresh"              # all three
///
/// A refresh refetches in place: it never switches tab, scrolls or brings the
/// window forward, so `open -g` leaves focus wherever the user is typing.
enum RunwayURLCommand {
    /// The tabs a link asks to refresh, or nil when it is not a refresh link.
    static func refreshTabs(in url: URL) -> [FeedTab]? {
        guard url.scheme?.lowercased() == "runway",
              url.host?.lowercased() == "refresh" else { return nil }

        let tab = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first(where: { $0.name == "tab" })?
            .value?
            .lowercased()

        switch tab {
        case nil, "", "all": return FeedTab.allCases
        case "runway", "issues": return [.runway]
        case "feeds", "feed": return [.feeds]
        case "pulls", "prs", "pullrequests": return [.pullRequests]
        default: return nil
        }
    }

    @MainActor
    static func handle(_ url: URL) {
        guard let tabs = refreshTabs(in: url) else { return }
        for context in RunwayWindowRegistry.shared.allContexts {
            for tab in tabs {
                context.workspace.requestSourceRefresh(tab)
            }
        }
    }
}
