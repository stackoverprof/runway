import Foundation

/// The crews of a flight, in the one order everything agrees on.
///
/// The right pane draws this list and the keyboard walks it, so neither may
/// work it out for itself: ⌘⌃3 has to mean the third card the pane is showing,
/// not the third leg GitHub happened to return.
@MainActor
enum FlightCrews {
    /// Every crew of the flight, landed ones last, in checklist order.
    static func all(in issues: AssignedIssues, flight: Int?) -> [IssueLeg] {
        let flight = issues.issue(flight)
        return CrewOrder.sorted(
            flight?.legs ?? [],
            by: IssueBody.steps("Progress", in: flight?.body ?? "")
        )
    }

    /// The crews on screen: still flying, plus any landed one brought back up.
    /// This is what a number key counts.
    static func flying(in issues: AssignedIssues, flight: Int?) -> [IssueLeg] {
        let deck = CrewDeck.shared
        return all(in: issues, flight: flight).filter { crew in
            !crew.isClosed || deck.isUp(repository(of: crew, in: issues), crew.number)
        }
    }

    /// Where a crew's issue lives, which is how the deck names its seat.
    static func repository(of crew: IssueLeg, in issues: AssignedIssues) -> String {
        crew.repository ?? issues.repository ?? ""
    }

    /// Bring a crew up if it is down, and read it. What a key press means.
    static func read(_ crew: IssueLeg, in issues: AssignedIssues, ws: Workspace) {
        let repository = repository(of: crew, in: issues)
        if !CrewDeck.shared.isUp(repository, crew.number) {
            CrewDeck.shared.bringUp(repository, crew.number, title: crew.title)
        }
        ws.readingCrew = crew.number
    }

    /// Stand the crew being read up, or down if it is already up. The crew
    /// is not lost when it stands down: the card stays, and the next press
    /// brings it back with its session intact.
    static func toggle(in issues: AssignedIssues, ws: Workspace) {
        let crews = all(in: issues, flight: ws.flightNumber)
        guard let number = ws.readingCrew,
              let crew = crews.first(where: { $0.number == number }) else {
            // Nothing is being read, so the first crew is what you meant.
            step(by: 1, in: issues, ws: ws)
            return
        }
        let repository = repository(of: crew, in: issues)
        if CrewDeck.shared.isUp(repository, crew.number) {
            CrewDeck.shared.standDown(repository, crew.number, title: crew.title)
            ws.readingCrew = nil
        } else {
            CrewDeck.shared.bringUp(repository, crew.number, title: crew.title)
        }
    }

    /// Step to the crew before or after the one being read. With none read,
    /// a step forward starts at the first.
    static func step(by delta: Int, in issues: AssignedIssues, ws: Workspace) {
        let crews = flying(in: issues, flight: ws.flightNumber)
        guard !crews.isEmpty else { return }
        guard let current = ws.readingCrew,
              let index = crews.firstIndex(where: { $0.number == current }) else {
            read(crews[delta > 0 ? 0 : crews.count - 1], in: issues, ws: ws)
            return
        }
        guard let next = SubtabNavigation.index(
            from: index,
            by: delta,
            count: crews.count
        ) else { return }
        read(crews[next], in: issues, ws: ws)
    }

    /// Jump to the nth crew on screen, counting from one.
    static func select(number: Int, in issues: AssignedIssues, ws: Workspace) {
        let crews = flying(in: issues, flight: ws.flightNumber)
        guard crews.indices.contains(number - 1) else { return }
        read(crews[number - 1], in: issues, ws: ws)
    }
}
