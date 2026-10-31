import SwiftUI

/// Where a flight is, in the words a controller would use.
///
/// Read from the issue itself: whether it is closed, how its checklist stands,
/// and whether any step says what it waits on. Two states (open and closed)
/// told you nothing you could not see; these say whether the flight is moving,
/// stuck, or nearly down.
enum FlightStatus: String {
    /// Nothing has moved yet: no step ticked, nothing waiting.
    case onTheStand = "on the stand"
    /// Moving: at least one step done, nothing blocking the next.
    case enRoute = "en route"
    /// A step says what it is waiting on, and it is not you who can move it on.
    case holding = "holding"
    /// Every step but the last is done; the flight is lining up to land.
    case onApproach = "on approach"
    /// The issue is closed.
    case landed = "landed"

    var label: String { rawValue.uppercased() }

    /// One scale, cool to warm, so the chips read as a journey rather than
    /// five unrelated colours.
    ///
    /// The three progress states climb slate, blue, mint: nothing has moved,
    /// it is moving, it is nearly down. Amber is kept for the one state that
    /// is not progress at all, a flight waiting on somebody, and it is the
    /// same amber that means "an agent wants you" everywhere else. Purple is
    /// closed, as it is on every other card. Teal is not used here: it names
    /// a flight elsewhere, and a colour should mean one thing.
    var color: Color {
        switch self {
        case .onTheStand: Color(red: 0.49, green: 0.54, blue: 0.59)
        case .enRoute: Color(red: 0.38, green: 0.60, blue: 0.93)
        case .holding: Runway.amber
        case .onApproach: Color(red: 0.25, green: 0.80, blue: 0.60)
        case .landed: Runway.purple
        }
    }

    /// `/close` is the pilot's own last line; it is not work, so it does not
    /// count toward how far along the flight is.
    static func of(closed: Bool, steps: [IssueBody.Step]) -> FlightStatus {
        if closed { return .landed }
        let work = steps.filter { $0.text.lowercased() != "/close" }
        guard !work.isEmpty else { return .onTheStand }
        let done = work.filter(\.done).count
        let remaining = work.filter { !$0.done }
        if remaining.isEmpty { return .onApproach }
        if remaining.contains(where: { $0.needs != nil }) { return .holding }
        if done == 0 { return .onTheStand }
        return remaining.count == 1 ? .onApproach : .enRoute
    }
}
