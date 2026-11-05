import Foundation

/// On a fresh open, the pinned pilots come up too, one at a time.
///
/// The flight on screen (the one you had open last) starts first, as it
/// always has, from its own pane. Then every pinned flight's pilot is put on
/// the deck in turn, waiting for each to be running before the next, so a
/// dozen sessions never start in the same second:
///
/// - last open flight is pinned: carry on down the pinned list from it, then
///   come back round to the ones above it;
/// - last open flight is not pinned: the pinned ones from the top down.
///
/// Runs once per launch. Quiet flights still doze on their own clock.
@MainActor
final class PilotWarmup {
    static let shared = PilotWarmup()
    private var done = false

    func runOnce(issues: AssignedIssues, ws: Workspace) {
        guard !done else { return }
        done = true
        Task { @MainActor in
            // The board and the flight on screen, once GitHub (or the cache)
            // has answered.
            for _ in 0..<60 where issues.repository == nil || issues.open.isEmpty || ws.flightNumber == nil {
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
            guard let repository = issues.repository else { return }
            let pool = TerminalSessionPool.shared
            @MainActor func pilot(_ number: Int) -> UUID {
                FlightCrewSessions.boxID(rank: .pilot, repository: repository, issue: number)
            }
            @MainActor func waitUntilLive(_ number: Int) async {
                for _ in 0..<40 where !pool.isLive(pilot(number)) {
                    try? await Task.sleep(nanoseconds: 500_000_000)
                }
            }

            let board = FlightBoard.shared
            let pinned = issues.open.filter { board.isPinned($0.number, in: repository) }
            guard !pinned.isEmpty else { return }

            // The one on screen first, and settled, before anything else.
            let current = ws.flightNumber
            if let current { await waitUntilLive(current) }

            var order = pinned
            if let current, let at = pinned.firstIndex(where: { $0.number == current }) {
                order = Array(pinned[(at + 1)...]) + Array(pinned[..<at])
            }
            for flight in order where !pool.isLive(pilot(flight.number)) {
                guard !flight.isClosed, ws.flightNumber != flight.number else { continue }
                PilotDeck.shared.bringUp(repository, flight.number, title: flight.title)
                await waitUntilLive(flight.number)
                // A beat between pilots, so each settles before the next.
                try? await Task.sleep(nanoseconds: 1_500_000_000)
            }
        }
    }
}
