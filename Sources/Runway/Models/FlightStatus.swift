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

    /// The checklist's closing line is the pilot's own; it is not work, so it
    /// does not count toward whether the flight has started.
    static func of(closed: Bool, steps: [IssueBody.Step]) -> FlightStatus {
        if closed { return .landed }
        let work = steps.filter { !$0.isLanding }
        return work.contains(where: \.done) ? .onAir : .scheduled
    }
}
