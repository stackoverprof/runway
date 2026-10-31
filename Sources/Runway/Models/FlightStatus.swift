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

    var color: Color {
        switch self {
        case .onTheStand: Color.white.opacity(0.42)
        case .enRoute: Runway.teal
        case .holding: Runway.amber
        case .onApproach: Runway.green
        // Purple is closed everywhere in Runway, and a landed flight is
        // closed. Green here read as "still going well".
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
