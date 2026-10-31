import AppKit
import SwiftUI

/// Dragging a flight to a new place on the board, the way v2 does it.
///
/// Not `onDrag`/`onDrop`: the system drag has its own pasteboard dance, its
/// own timing and its own idea of where the pointer is, and it fought the
/// list. A plain drag gesture in one named coordinate space, with every card
/// reporting its live frame, is what made v2's reordering feel solid: the
/// card follows the pointer exactly, the list reorders as you cross a
/// neighbour's midpoint, and the order is written once when you let go.
@MainActor
@Observable
final class FlightDrag {
    static let space = "runway.flights"

    /// The flight being dragged, if one is.
    private(set) var issue: Int?
    /// Where the floating card sits, in the list's coordinate space.
    private(set) var origin: CGPoint = .zero
    private(set) var size: CGSize = .zero

    /// Each card's own frame, straight from its geometry. A preference-based
    /// copy lags a list that just reordered, which put the floating card a
    /// row or two away from the one grabbed.
    @ObservationIgnored private var frames: [Int: CGRect] = [:]
    @ObservationIgnored private var grabOffset: CGSize = .zero
    @ObservationIgnored private var lastTarget: Int?

    func report(_ number: Int, frame: CGRect) {
        frames[number] = frame
    }

    func forget(_ number: Int) {
        frames.removeValue(forKey: number)
    }

    var isDragging: Bool { issue != nil }

    /// Start, with the card's frame checked against the pointer that grabbed
    /// it, so a stale frame cannot teleport the card.
    func begin(_ number: Int, at pointer: CGPoint) {
        guard let frame = frames[number], frame.contains(pointer) else { return }
        issue = number
        size = frame.size
        grabOffset = CGSize(
            width: pointer.x - frame.minX,
            height: pointer.y - frame.minY
        )
        origin = frame.origin
        lastTarget = nil
    }

    func move(to pointer: CGPoint) {
        origin = CGPoint(x: pointer.x - grabOffset.width, y: pointer.y - grabOffset.height)
    }

    /// The flight the pointer is over, once it is past that card's midpoint,
    /// and only when it is a different one than last time. Without both the
    /// list flaps between two orders as the pointer sits on a boundary.
    func target(at pointer: CGPoint, excluding moving: Int) -> Int? {
        for (number, frame) in frames where number != moving {
            guard frame.contains(pointer) else { continue }
            guard number != lastTarget else { return nil }
            lastTarget = number
            return number
        }
        return nil
    }

    func end() {
        issue = nil
        lastTarget = nil
        size = .zero
    }
}

/// The card that follows the pointer while a flight is being dragged.
struct FlightDragCard: View {
    let drag: FlightDrag
    let issue: AssignedIssue
    let repository: String
    var boardKey: String = ""

    var body: some View {
        AssignedIssueCard(issue: issue, repository: repository, boardKey: boardKey)
            .frame(width: drag.size.width, height: drag.size.height)
            .offset(x: drag.origin.x, y: drag.origin.y)
            .shadow(color: .black.opacity(0.38), radius: 12, y: 5)
            .allowsHitTesting(false)
    }
}

/// Makes one card draggable, and reports its frame while it sits in the list.
struct DraggableFlight: ViewModifier {
    let enabled: Bool
    let issue: Int
    let lane: [Int]
    let repository: String
    let drag: FlightDrag

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGRect.self) { proxy in
                proxy.frame(in: .named(FlightDrag.space))
            } action: { frame in
                drag.report(issue, frame: frame)
            }
            .onDisappear { drag.forget(issue) }
            // Simultaneous, as v2 has it: the card already has a tap that
            // picks the flight, and a plain `.gesture` loses to it, so the
            // drag never started.
            .simultaneousGesture(enabled ? reorder : nil)
    }

    /// A short minimum distance so a click still selects the flight, and the
    /// list reorders live as the pointer crosses a neighbour.
    private var reorder: some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .named(FlightDrag.space))
            .onChanged { value in
                if drag.issue == nil {
                    let start = CGPoint(
                        x: value.location.x - value.translation.width,
                        y: value.location.y - value.translation.height
                    )
                    drag.begin(issue, at: start)
                }
                guard drag.issue == issue else { return }
                drag.move(to: value.location)
                guard let over = drag.target(at: value.location, excluding: issue),
                      let from = lane.firstIndex(of: issue),
                      let to = lane.firstIndex(of: over),
                      !repository.isEmpty
                else { return }
                var next = lane
                next.remove(at: from)
                next.insert(issue, at: to)
                withAnimation(.easeInOut(duration: 0.16)) {
                    FlightBoard.shared.setOrder(next, in: repository)
                }
            }
            .onEnded { _ in
                withAnimation(.easeInOut(duration: 0.18)) { drag.end() }
            }
    }
}
