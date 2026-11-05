import AppKit
import GhosttyKit

/// Starts the seats that are wanted but not on screen.
///
/// `runway crew up` and `runway pilot up` only write a deck. A seat's agent
/// used to start when a view showed it, so a pilot raising crews for a flight
/// you were not looking at got nothing: the deck said up, no session ran.
/// Mounting those seats from the panes was worse, since it started processes
/// inside a SwiftUI pass and froze the window on every pause.
///
/// The hangar does it outside any view. Every couple of seconds it reads the
/// decks, and for each seat that is up but has no terminal yet it makes one
/// through the pool and parks its view in a window that is never shown. One
/// seat at a time, a beat apart, so a pilot raising five crews does not stall
/// the app. When you open the flight later, the pane gets the same session
/// from the pool and moves the view on screen; nothing restarts.
@MainActor
final class Hangar {
    static let shared = Hangar()

    /// Seats some deck holds up. The pool never lets one of these go for
    /// being idle off screen: the deck is the request to keep it running.
    private(set) var wanted: Set<UUID> = []

    private struct Pending {
        let id: UUID
        let config: TerminalConfig
    }

    private var queue: [Pending] = []
    private var draining = false
    private var window: NSWindow?
    private static let size = NSSize(width: 1000, height: 700)

    func sync(issues: AssignedIssues) {
        guard let fallback = issues.repository else { return }
        var next: Set<UUID> = []
        for flight in issues.issues where flight.parent == nil && !flight.isClosed {
            if PilotDeck.shared.isUp(fallback, flight.number) {
                let id = FlightCrewSessions.boxID(rank: .pilot, repository: fallback, issue: flight.number)
                next.insert(id)
                want(id) {
                    FlightCrewSessions.config(
                        rank: .pilot,
                        repository: fallback,
                        issue: flight.number,
                        title: flight.title,
                        flight: flight.number,
                        reportsTo: "you"
                    )
                }
            }
            for leg in flight.legs where !leg.isClosed {
                let repository = leg.repository ?? fallback
                guard CrewDeck.shared.isUp(repository, leg.number) else { continue }
                let id = FlightCrewSessions.boxID(rank: .crew, repository: repository, issue: leg.number)
                next.insert(id)
                want(id) {
                    FlightCrewSessions.config(
                        rank: .crew,
                        repository: repository,
                        issue: leg.number,
                        title: leg.title,
                        flight: flight.number,
                        reportsTo: FlightCrewSessions.sessionName(
                            rank: .pilot,
                            repository: repository,
                            issue: flight.number,
                            title: ""
                        )
                    )
                }
            }
        }
        if next != wanted { wanted = next }
        queue.removeAll { !wanted.contains($0.id) }
        drain()
    }

    private func want(_ id: UUID, config: () -> TerminalConfig) {
        guard !TerminalSessionPool.shared.isLive(id),
              !queue.contains(where: { $0.id == id }) else { return }
        queue.append(Pending(id: id, config: config()))
    }

    private func drain() {
        guard !draining, !queue.isEmpty else { return }
        draining = true
        Task { @MainActor in
            while !queue.isEmpty {
                let next = queue.removeFirst()
                start(next)
                try? await Task.sleep(nanoseconds: 1_200_000_000)
            }
            draining = false
        }
    }

    private func start(_ seat: Pending) {
        let pool = TerminalSessionPool.shared
        guard !pool.isLive(seat.id) else { return }
        let launch = GhosttyTerminalLaunchConfiguration(
            command: seat.config.command,
            workingDirectory: seat.config.workingDirectory,
            environment: seat.config.environment,
            colorScheme: .dark
        )
        let session = pool.session(for: seat.id, launch: launch)
        // The process starts when the surface does, and the surface needs its
        // view in a window. A pane may have shown it in the meantime.
        guard session.view == nil else { return }
        let view = session.makeView(configuration: .default)
        view.frame = NSRect(origin: .zero, size: Self.size)
        hangarWindow().contentView?.addSubview(view)
        pool.parked(seat.id)
    }

    /// Take a seat's view out of the hidden window before its session goes,
    /// so nothing here keeps the terminal alive.
    func evict(_ id: UUID) {
        guard let window, let view = TerminalSessionPool.shared.anySession(id)?.view,
              view.window === window else { return }
        view.removeFromSuperview()
    }

    private func hangarWindow() -> NSWindow {
        if let window { return window }
        let made = NSWindow(
            contentRect: NSRect(origin: NSPoint(x: -20_000, y: -20_000), size: Self.size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        made.isReleasedWhenClosed = false
        made.contentView = NSView(frame: NSRect(origin: .zero, size: Self.size))
        window = made
        return made
    }
}
