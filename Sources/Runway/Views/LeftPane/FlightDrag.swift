import AppKit
import SwiftUI

/// Dragging a flight to a new place, as v2 does it.
///
/// Not the system drag: a plain gesture, every card reporting its own live
/// frame, and the pointer taken from the window rather than from the
/// gesture. That last part is what makes it feel solid. A gesture's own
/// location is reported in the space the view was in when the event was
/// queued, so during a fast drag over a list that is reordering underneath
/// it, the readings lag and the card jumps. The window always knows where
/// the mouse is.
@MainActor
@Observable
final class FlightDrag {
    static let space = "runway.flights"

    private(set) var issue: Int?
    private(set) var origin: CGPoint = .zero
    private(set) var size: CGSize = .zero

    /// Each card's frame, straight from its own geometry rather than a
    /// preference pass, which lags a list that has just reordered.
    ///
    /// Kept per lane. The open and the closed list are two scroll views at
    /// the same place on screen, both full of cards, and both report. In one
    /// shared map the closed lane's frames sat on top of the open lane's, so
    /// the card you dropped landed next to a closed issue that is not even in
    /// the lane, and the reorder fell through to "put it last".
    @ObservationIgnored private var frames: [String: [Int: CGRect]] = [:]
    /// Where each lane's coordinate space sits in the window, so a window
    /// pointer can be read in that list's own terms.
    @ObservationIgnored private var spaceOrigins: [String: CGPoint] = [:]
    @ObservationIgnored private var grabOffset: CGSize = .zero
    @ObservationIgnored private var lastTarget: Int?

    var isDragging: Bool { issue != nil }

    func report(_ number: Int, lane: String, frame: CGRect) {
        frames[lane, default: [:]][number] = frame
    }

    func forget(_ number: Int, lane: String) {
        frames[lane]?.removeValue(forKey: number)
    }

    func reportSpace(_ frame: CGRect, lane: String) {
        spaceOrigins[lane] = frame.origin
    }

    /// Where the mouse is, in this list's coordinates. Falls back to the
    /// gesture's own idea when the window cannot say.
    func pointer(_ location: CGPoint, lane: String) -> CGPoint {
        guard let window = NSApp.keyWindow ?? NSApp.mainWindow,
              let content = window.contentView,
              let origin = spaceOrigins[lane] else { return location }
        let local = content.convert(window.mouseLocationOutsideOfEventStream, from: nil)
        let inWindow = content.isFlipped
            ? local
            : CGPoint(x: local.x, y: content.bounds.height - local.y)
        return CGPoint(x: inWindow.x - origin.x, y: inWindow.y - origin.y)
    }

    /// The grabbed card's frame, checked against the pointer that grabbed
    /// it. A frame that does not contain the pointer is stale, and starting
    /// from it puts the floating card a row away from the one grabbed.
    func begin(_ number: Int, lane: String, at pointer: CGPoint) {
        guard let frame = frames[lane]?[number] else { return }
        let grabbed = frame.contains(pointer)
            ? frame
            : CGRect(
                x: frame.minX,
                y: pointer.y - frame.height / 2,
                width: frame.width,
                height: frame.height
            )
        issue = number
        size = grabbed.size
        origin = grabbed.origin
        grabOffset = CGSize(
            width: pointer.x - grabbed.minX,
            height: pointer.y - grabbed.minY
        )
        lastTarget = nil
    }

    func move(to pointer: CGPoint) {
        origin = CGPoint(x: pointer.x - grabOffset.width, y: pointer.y - grabOffset.height)
    }

    /// Where the dragged card would land: the first card, top to bottom,
    /// whose middle the pointer is above. Nil means the end of the list.
    func insertion(at pointer: CGPoint, excluding moving: Int, lane: String) -> Int? {
        (frames[lane] ?? [:])
            .filter { $0.key != moving && !$0.value.isEmpty }
            .sorted { $0.value.minY < $1.value.minY }
            .first { pointer.y < $0.value.midY }?
            .key
    }

    /// True once, when the target changes. Without it the list flaps between
    /// two orders while the pointer sits on a boundary.
    func shouldMove(to target: Int?) -> Bool {
        guard lastTarget != target else { return false }
        lastTarget = target
        return true
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
    /// Which list this card is in, so its frame cannot be mistaken for a
    /// card of the other one.
    let laneKey: String
    let lane: [Int]
    let repository: String
    let drag: FlightDrag

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGRect.self) { proxy in
                proxy.frame(in: .named(FlightDrag.space))
            } action: { frame in
                drag.report(issue, lane: laneKey, frame: frame)
            }
            .onDisappear { drag.forget(issue, lane: laneKey) }
            // Simultaneous: the card already has a tap that picks the
            // flight, and a plain gesture loses to it.
            .simultaneousGesture(enabled ? reorder : nil)
    }

    private var reorder: some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .named(FlightDrag.space))
            .onChanged { value in
                let now = drag.pointer(value.location, lane: laneKey)
                if drag.issue == nil {
                    // Where the drag started, so the grab is checked against
                    // the card the pointer was actually on.
                    let start = CGPoint(
                        x: now.x - value.translation.width,
                        y: now.y - value.translation.height
                    )
                    drag.begin(issue, lane: laneKey, at: start)
                }
                guard drag.issue == issue, !repository.isEmpty else { return }
                drag.move(to: now)

                let before = drag.insertion(at: now, excluding: issue, lane: laneKey)
                guard drag.shouldMove(to: before) else { return }
                var next = lane.filter { $0 != issue }
                if let before, let at = next.firstIndex(of: before) {
                    next.insert(issue, at: at)
                } else {
                    next.append(issue)
                }
                guard next != lane else { return }
                withAnimation(.easeInOut(duration: 0.16)) {
                    FlightBoard.shared.setOrder(next, in: repository)
                }
            }
            .onEnded { _ in
                withAnimation(.easeInOut(duration: 0.18)) { drag.end() }
            }
    }
}
