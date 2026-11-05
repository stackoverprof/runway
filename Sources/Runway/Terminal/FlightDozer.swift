import AppKit
import Foundation
import Observation

/// Stops a flight's Claude sessions once the whole flight has gone quiet.
///
/// A flight dozes when its pilot, copilot and every crew have all been idle
/// for the flight's limit (Settings > Flights): 30 minutes for a pinned
/// flight, 15 for the rest by default. Typing into any of its seats counts as
/// activity too. The flight on screen never dozes.
///
/// Dozing stands the flight down on both decks, so the hangar does not start
/// it straight back up, and lets each session go. Nothing is lost: a seat's
/// next start resumes its own conversation. Opening the flight brings the
/// pilot back; a pilot (or the ATC) raising a crew brings that crew back.
@MainActor
@Observable
final class FlightDozer {
    static let shared = FlightDozer()

    static let pinnedKey = "runway.idleStopPinnedMinutes"
    static let otherKey = "runway.idleStopMinutes"

    /// Flights let go, so the middle pane stops holding their pilots mounted.
    /// Cleared when you open the flight again.
    private(set) var dozing: Set<Int> = []

    @ObservationIgnored private var lastBusy: [UUID: Date] = [:]
    @ObservationIgnored private var lastCheck: Date = .distantPast

    static func limit(pinned: Bool) -> TimeInterval {
        let key = pinned ? pinnedKey : otherKey
        let set = UserDefaults.standard.integer(forKey: key)
        let minutes = set > 0 ? set : (pinned ? 30 : 15)
        return TimeInterval(minutes * 60)
    }

    func wake(_ number: Int) {
        if dozing.contains(number) { dozing.remove(number) }
    }

    /// Called every second from the window loop; does its work every 20.
    func sync(issues: AssignedIssues, onScreen: Int?) {
        let now = Date()
        guard now.timeIntervalSince(lastCheck) >= 20, let board = issues.repository else { return }
        lastCheck = now
        let pool = TerminalSessionPool.shared

        for flight in issues.issues where flight.parent == nil && !flight.isClosed {
            var seats: [(id: UUID, crew: IssueLeg?)] = [.pilot, .copilot].map { rank in
                (FlightCrewSessions.boxID(rank: rank, repository: board, issue: flight.number), nil)
            }
            for leg in flight.legs where !leg.isClosed {
                let repository = leg.repository ?? board
                seats.append((FlightCrewSessions.boxID(rank: .crew, repository: repository, issue: leg.number), leg))
            }
            let live = seats.filter { pool.isLive($0.id) }
            guard !live.isEmpty else { continue }

            // First sighting, or busy now: the clock starts from here.
            var quietSince = Date.distantPast
            for seat in live {
                if lastBusy[seat.id] == nil || TerminalSessionPool.isBusy(seat.id) {
                    lastBusy[seat.id] = now
                }
                quietSince = max(quietSince, lastBusy[seat.id] ?? now)
            }
            if let touched = FlightActivity.shared.lastTouched(flight) {
                quietSince = max(quietSince, touched)
            }

            guard flight.number != onScreen else { continue }
            let pinned = FlightBoard.shared.isPinned(flight.number, in: board)
            guard now.timeIntervalSince(quietSince) > Self.limit(pinned: pinned) else { continue }

            PilotDeck.shared.standDown(board, flight.number, title: flight.title)
            for seat in live {
                if let leg = seat.crew {
                    CrewDeck.shared.standDown(leg.repository ?? board, leg.number, title: leg.title)
                }
                Hangar.shared.evict(seat.id)
                pool.release(seat.id)
                lastBusy.removeValue(forKey: seat.id)
            }
            dozing.insert(flight.number)
            NSLog("Runway: flight #\(flight.number) idle, its \(live.count) session(s) stopped")
        }
    }
}
