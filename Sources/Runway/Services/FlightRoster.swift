import Foundation

/// The flights the left pane is showing, and the keyboard's way through them.
///
/// Which lane is in front matters: ⌘1 means the first card you can see, so on
/// the Closed lane it means the first landed flight, not the first open one.
@MainActor
enum FlightRoster {
    static func visible(in issues: AssignedIssues, ws: Workspace) -> [AssignedIssue] {
        ws.runwayIssueTab == .open ? issues.open : issues.closed
    }

    static func fly(_ issue: AssignedIssue, ws: Workspace, reveal: Bool = true) {
        if reveal { ws.revealFlight() }
        guard ws.flightNumber != issue.number else { return }
        ws.flightNumber = issue.number
        // A new flight has its own crews, so whichever one was being read
        // belongs to the flight you just left.
        ws.readingCrew = nil
    }

    /// Jump to the nth flight in the lane, counting from one.
    static func select(number: Int, in issues: AssignedIssues, ws: Workspace) {
        let flights = visible(in: issues, ws: ws)
        guard flights.indices.contains(number - 1) else { return }
        fly(flights[number - 1], ws: ws)
    }

    /// The flight before or after the one being flown. Wraps, and with none
    /// flown a step forward starts at the top of the lane.
    static func step(by delta: Int, in issues: AssignedIssues, ws: Workspace) {
        let flights = visible(in: issues, ws: ws)
        guard !flights.isEmpty else { return }
        guard let current = ws.flightNumber,
              let index = flights.firstIndex(where: { $0.number == current }) else {
            fly(flights[delta > 0 ? 0 : flights.count - 1], ws: ws)
            return
        }
        guard let next = SubtabNavigation.index(
            from: index,
            by: delta,
            count: flights.count
        ) else { return }
        fly(flights[next], ws: ws)
    }
}
