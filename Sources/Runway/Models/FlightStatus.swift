import SwiftUI

/// Where a flight is, in the words a controller would use.
///
/// Read from the issue itself, never set by hand: whether it is closed, and
/// whether any work has started. Three states, because three is what you act
/// on. Finer grades (nearly down, waiting on somebody) were a colour you had
/// to decode, and the checklist already says which step is where.
enum FlightStatus: String {
    /// Filed, nothing started: no step of its checklist is ticked.
    case scheduled = "scheduled"
    /// Work has begun and the issue is still open.
    case onAir = "on air"
    /// The issue is closed.
    case landed = "landed"

    var label: String { rawValue.uppercased() }

    /// Slate while it waits, teal while it is live, purple once it is down.
    /// Teal is Runway's own colour, the one the flight number already wears,
    /// so a flight in the air reads in the colour of the thing it is. Green
    /// stays out of it: that means "an agent is running".
    var color: Color {
        switch self {
        case .scheduled: Color(red: 0.49, green: 0.54, blue: 0.59)
        case .onAir: Runway.teal
        case .landed: Runway.purple
        }
    }

    /// How far along the flight is: how many steps of its checklist are
    /// ticked out of how many there are.
    ///
    /// The checklist, not the crews. Progress is what the pilot actually
    /// keeps: it covers work that is nobody's crew, a merge, a deploy, a
    /// word to a teammate, and it changes as the work changes. Counting
    /// crews measured only how the work happened to be filed, so the card
    /// and the route bar in the pane told two different stories about the
    /// same flight.
    ///
    /// The closing line is the pilot's own and is not work, so it never
    /// counts. A flight with no checklist at all falls back to its crews,
    /// which is better than printing nothing.
    static func miles(of issue: AssignedIssue) -> (done: Int, total: Int) {
        let work = IssueBody.steps("Progress", in: issue.body).filter { !$0.isLanding }
        if work.isEmpty, issue.isFlight { return (issue.landedLegs, issue.legs.count) }
        return (work.filter(\.done).count, work.count)
    }

    static func of(_ issue: AssignedIssue) -> FlightStatus {
        if issue.isClosed { return .landed }
        let flown = miles(of: issue)
        return flown.done > 0 ? .onAir : .scheduled
    }

    /// The checklist's closing line is the pilot's own; it is not work, so it
    /// does not count toward whether the flight has started.
    static func of(closed: Bool, steps: [IssueBody.Step]) -> FlightStatus {
        if closed { return .landed }
        let work = steps.filter { !$0.isLanding }
        return work.contains(where: \.done) ? .onAir : .scheduled
    }
}
