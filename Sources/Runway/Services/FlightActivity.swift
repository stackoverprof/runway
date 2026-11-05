import AppKit
import Foundation
import Observation

/// When you last touched each flight: opened it, or typed into its pilot or
/// one of its crews. What "Most recent first" sorts by.
///
/// Your activity, not GitHub's. T3 Code moves a thread when you send it a
/// message and Orca when you visit or an agent reports; neither moves a row
/// because a body was edited. Sorting by GitHub's `updatedAt` made the lane
/// reshuffle every time a pilot rewrote Progress.
///
/// The lane reads `settled`, a copy taken three seconds after the last
/// touch (Orca's settle window), so typing into a pilot does not make the
/// list jump on every key.
@MainActor
@Observable
final class FlightActivity {
    static let shared = FlightActivity()

    /// A new flight stays near the top this long before it competes on
    /// touches alone, as Orca does for a new workspace.
    static let newFlightGrace: TimeInterval = 5 * 60
    private static let settleDelay: Duration = .seconds(3)

    /// What the lane sorts by. Changes only when a burst of touches settles.
    private(set) var settled: [String: Date] = [:]
    @ObservationIgnored private var touched: [String: Date] = [:]
    @ObservationIgnored private var settleTask: Task<Void, Never>?
    @ObservationIgnored private var lastSaved: Date = .distantPast

    private var file: URL {
        RunwayStorage.supportDir.appendingPathComponent("flight-activity.json")
    }

    private init() {
        if let data = try? Data(contentsOf: file),
           let decoded = try? JSONDecoder().decode([String: Date].self, from: data) {
            touched = decoded
            settled = decoded
        }
    }

    /// Keyed by the issue's URL, which names the repository and the number.
    func touch(_ flight: AssignedIssue) { touch(url: flight.url) }

    func touch(url: URL) {
        let now = Date()
        // A keystroke arrives many times a second; a minute is plenty.
        if let last = touched[url.absoluteString], now.timeIntervalSince(last) < 60 { return }
        touched[url.absoluteString] = now
        scheduleSettle()
    }

    /// The last touch, settled or not, for the idle check.
    func lastTouched(_ flight: AssignedIssue) -> Date? {
        touched[flight.url.absoluteString]
    }

    func rank(_ flight: AssignedIssue, now: Date = Date()) -> Date {
        let touch = settled[flight.url.absoluteString] ?? .distantPast
        guard let created = flight.createdAt else { return touch }
        let graceEnds = created.addingTimeInterval(Self.newFlightGrace)
        return max(touch, now < graceEnds ? graceEnds : created)
    }

    private func scheduleSettle() {
        settleTask?.cancel()
        settleTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: Self.settleDelay)
            guard !Task.isCancelled, let self else { return }
            self.settled = self.touched
            self.save()
        }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(touched) else { return }
        try? FileManager.default.createDirectory(at: RunwayStorage.supportDir, withIntermediateDirectories: true)
        try? data.write(to: file, options: .atomic)
    }

    /// A key typed into a seat counts as touching that seat's flight.
    /// Called from the app's key monitor; never swallows the event.
    static func noteKey(_ event: NSEvent, issues: AssignedIssues) {
        guard event.type == .keyDown,
              let responder = event.window?.firstResponder as? NSView,
              let id = TerminalSessionPool.shared.seat(holding: responder),
              let seat = FlightCrewSessions.seat(for: id) else { return }
        let flight: AssignedIssue?
        switch seat.rank {
        case .pilot, .copilot:
            flight = issues.issue(seat.issue)
        case .crew:
            flight = issues.issues.first { candidate in
                candidate.parent == nil && candidate.legs.contains { $0.number == seat.issue }
            }
        default:
            flight = nil
        }
        if let flight { shared.touch(flight) }
    }
}
