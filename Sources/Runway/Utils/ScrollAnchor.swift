import SwiftUI
import AppKit

/// Speed curve for dragging a card toward a scroll view's edge.
///
/// Pure so the ramp can be reasoned about without a live scroll view: negative
/// pulls the content toward its start (up), positive toward its end (down), and
/// zero means the pointer is in the calm middle of the lane.
enum EdgeAutoScrollPolicy {
    /// Height of the hot zone at each edge, in points.
    static let zone: CGFloat = 46
    /// Fastest step applied per animation tick (~60 Hz), in points.
    static let maxStep: CGFloat = 17

    static func step(
        pointerY: CGFloat,
        in frame: CGRect,
        zone: CGFloat = zone,
        maxStep: CGFloat = maxStep
    ) -> CGFloat {
        guard frame.height > zone * 2, zone > 0 else { return 0 }
        if pointerY < frame.minY + zone {
            let depth = min(1, (frame.minY + zone - pointerY) / zone)
            return -ramp(depth) * maxStep
        }
        if pointerY > frame.maxY - zone {
            let depth = min(1, (pointerY - (frame.maxY - zone)) / zone)
            return ramp(depth) * maxStep
        }
        return 0
    }

    /// Ease-in so the list creeps near the edge and accelerates past it, instead
    /// of jumping to full speed the moment the card touches the hot zone.
    private static func ramp(_ depth: CGFloat) -> CGFloat {
        let clamped = min(max(depth, 0), 1)
        return clamped * clamped
    }
}

/// A handle on the `NSScrollView` backing a SwiftUI `ScrollView`, so Runway can
/// scroll it itself: to the top when a tab is re-tapped, and continuously while
/// a Focus card is dragged against an edge.
@MainActor final class RunwayScrollAnchor {
    private weak var scrollView: NSScrollView?
    private var tickTask: Task<Void, Never>?
    private var step: CGFloat = 0

    func attach(_ scrollView: NSScrollView?) {
        guard scrollView !== self.scrollView else { return }
        self.scrollView = scrollView
    }

    // MARK: Scroll to top

    func scrollToTop(animated: Bool = true) {
        guard let scrollView, let documentView = scrollView.documentView else { return }
        let clip = scrollView.contentView
        let target = CGPoint(x: clip.bounds.origin.x, y: startY(scrollView, documentView))
        guard abs(clip.bounds.origin.y - target.y) > 0.5 else { return }
        guard animated else {
            clip.setBoundsOrigin(target)
            scrollView.reflectScrolledClipView(clip)
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.24
            context.allowsImplicitAnimation = true
            clip.animator().setBoundsOrigin(target)
            scrollView.reflectScrolledClipView(clip)
        }
    }

    // MARK: Edge auto-scroll during a drag

    /// Feed the drag pointer in; the lane keeps scrolling for as long as the
    /// pointer stays in an edge zone.
    func autoScroll(pointerY: CGFloat, in frame: CGRect) {
        step = EdgeAutoScrollPolicy.step(pointerY: pointerY, in: frame)
        guard step != 0 else { return stopAutoScroll() }
        guard tickTask == nil else { return }
        tickTask = Task { @MainActor [weak self] in
            while !Task.isCancelled, let self, self.step != 0 {
                self.applyStep()
                do {
                    try await Task.sleep(nanoseconds: 16_000_000)
                } catch {
                    break
                }
            }
            self?.tickTask = nil
        }
    }

    func stopAutoScroll() {
        step = 0
        tickTask?.cancel()
        tickTask = nil
    }

    private func applyStep() {
        guard let scrollView, let documentView = scrollView.documentView else { return }
        let clip = scrollView.contentView
        // A flipped document (SwiftUI's usual layout) grows downward, so a
        // positive step raises the origin. An unflipped one is the mirror.
        let delta = documentView.isFlipped ? step : -step
        let minY = startY(scrollView, documentView)
        let maxY = max(minY, documentView.frame.height - clip.bounds.height)
        let nextY = min(max(minY, clip.bounds.origin.y + delta), maxY)
        guard abs(nextY - clip.bounds.origin.y) > 0.01 else { return }
        clip.setBoundsOrigin(CGPoint(x: clip.bounds.origin.x, y: nextY))
        scrollView.reflectScrolledClipView(clip)
    }

    private func startY(_ scrollView: NSScrollView, _ documentView: NSView) -> CGFloat {
        documentView.isFlipped
            ? -scrollView.contentInsets.top
            : max(0, documentView.frame.height - scrollView.contentView.bounds.height)
    }
}

/// Drop this inside a `ScrollView`'s content to hand the enclosing
/// `NSScrollView` to an anchor. Zero-sized, so it never affects layout.
struct ScrollAnchorProbe: NSViewRepresentable {
    let anchor: RunwayScrollAnchor

    func makeNSView(context: Context) -> ProbeView {
        let view = ProbeView()
        view.anchor = anchor
        return view
    }

    func updateNSView(_ nsView: ProbeView, context: Context) {
        nsView.anchor = anchor
        nsView.locate()
    }

    final class ProbeView: NSView {
        weak var anchor: RunwayScrollAnchor?

        override var intrinsicContentSize: NSSize { .zero }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            locate()
        }

        func locate() {
            guard let anchor, let scrollView = enclosingScrollView else { return }
            anchor.attach(scrollView)
        }
    }
}

extension View {
    /// Register this scroll view's content with `anchor`.
    func scrollAnchor(_ anchor: RunwayScrollAnchor) -> some View {
        background {
            ScrollAnchorProbe(anchor: anchor)
                .frame(width: 0, height: 0)
                .allowsHitTesting(false)
        }
    }
}
