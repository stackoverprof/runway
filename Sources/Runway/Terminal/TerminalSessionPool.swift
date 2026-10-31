import Foundation
import GhosttyKit

/// Terminals that outlive the view showing them.
///
/// Switching flights unmounts the old flight's seats, and a SwiftUI `@State`
/// session dies with its view: the agent was killed and started again the
/// moment you came back. The pool holds a seat's session by its box id, so
/// leaving a flight only parks it. A session is let go once it has been off
/// screen for `buffer`, and the pool never parks more than `capacity` of them.
///
/// Only an idle seat is ever let go. An agent that is still working, or that
/// has stopped to ask you something, keeps its terminal however long it sits
/// off screen: killing it would throw away the work or the question. That
/// makes `capacity` a soft cap, which is the right way round.
@MainActor
final class TerminalSessionPool {
    static let shared = TerminalSessionPool()

    /// How long a seat keeps running after you leave it.
    static let buffer: TimeInterval = 15 * 60
    /// How many parked seats to hold at once, oldest let go first.
    static let capacity = 12

    private struct Parked {
        let session: GhosttyTerminalSession
        var mounted: Bool
        var leftAt: Date
    }

    private var seats: [UUID: Parked] = [:]
    private var sweeper: Timer?

    private init() {
        sweeper = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { _ in
            Task { @MainActor in TerminalSessionPool.shared.sweep() }
        }
    }

    /// The seat's terminal, started the first time and handed back after that.
    func session(
        for boxID: UUID,
        launch: GhosttyTerminalLaunchConfiguration
    ) -> GhosttyTerminalSession {
        if let parked = seats[boxID] {
            seats[boxID]?.leftAt = Date()
            return parked.session
        }
        let session = RunwayTerminalHost.shared
            .map { $0.makeSession(configuration: launch) }
            ?? GhosttyTerminalSession(configuration: launch)
        seats[boxID] = Parked(session: session, mounted: false, leftAt: Date())
        // No sweep here: this runs inside a SwiftUI body pass, and letting a
        // session go there tears an NSView down mid-layout, which is what
        // hung the app when you switched flights. The timer sweeps instead.
        return session
    }

    func mounted(_ boxID: UUID) {
        seats[boxID]?.mounted = true
        seats[boxID]?.leftAt = Date()
    }

    /// Off screen, still running. The sweep decides when it has waited enough.
    func parked(_ boxID: UUID) {
        seats[boxID]?.mounted = false
        seats[boxID]?.leftAt = Date()
    }

    /// Let a seat go now, whatever the buffer says. Used when its flight or
    /// crew is gone for good, not when you merely look elsewhere.
    ///
    /// The drop happens on the next turn of the run loop, never inside the
    /// caller, so a session is not deallocated while SwiftUI is laying out
    /// the view that was showing it.
    func release(_ boxID: UUID) {
        guard let parked = seats.removeValue(forKey: boxID) else { return }
        TerminalRegistry.shared.unregister(id: boxID)
        Task { @MainActor in _ = parked }
    }

    var liveCount: Int { seats.count }

    func isLive(_ boxID: UUID) -> Bool { seats[boxID] != nil }

    /// Whether this seat's agent is mid-turn or waiting on an answer. Read
    /// from the control file its hooks write, the same one the header dot uses.
    static func isBusy(_ boxID: UUID) -> Bool {
        let file = AgentControl.controlDir
            .appendingPathComponent("\(boxID.uuidString).json")
        guard let data = try? Data(contentsOf: file),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let state = json["state"] as? String else { return false }
        return AgentState(control: state) != .idle
    }

    /// A seat the sweep may let go: off screen, and its agent has nothing in
    /// hand.
    private func isReleasable(_ id: UUID, _ seat: Parked) -> Bool {
        !seat.mounted && !Self.isBusy(id)
    }

    /// Drop what has been off screen past the buffer, then trim the oldest
    /// idle seats until the pool fits.
    func sweep(now: Date = Date()) {
        for (id, seat) in seats where isReleasable(id, seat) {
            if now.timeIntervalSince(seat.leftAt) > Self.buffer { release(id) }
        }
        var idle = seats.filter { isReleasable($0.key, $0.value) }
        while seats.count > Self.capacity,
              let oldest = idle.min(by: { $0.value.leftAt < $1.value.leftAt }) {
            release(oldest.key)
            idle.removeValue(forKey: oldest.key)
        }
    }
}
