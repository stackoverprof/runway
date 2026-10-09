import SwiftUI
import AppKit

/// The two ends of the Focus window, where hidden cards wait.
enum FocusReelEdge: Hashable {
    case above
    case below

    /// The window step that reveals a card on this side.
    var step: Int { self == .above ? -1 : 1 }
}

struct FocusReelEdgeFramePreferenceKey: PreferenceKey {
    static let defaultValue: [FocusReelEdge: CGRect] = [:]

    static func reduce(
        value: inout [FocusReelEdge: CGRect],
        nextValue: () -> [FocusReelEdge: CGRect]
    ) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

/// "▲ 1" / "▼ 2": how many cards sit past this end of the window. Styled
/// like the Quick Agent tab strip so it reads as a quiet control, not a card.
struct FocusReelEdgeButton: View {
    let edge: FocusReelEdge
    let count: Int
    /// A dragged card is hovering here, so the window is about to step.
    let isDropTarget: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: edge == .above ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill")
                    .font(.system(size: 7, weight: .semibold))
                Text("\(count)")
                    .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
            }
            .foregroundStyle(Color.white.opacity(highlighted ? 0.9 : 0.42))
            .frame(maxWidth: .infinity, minHeight: 18)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(highlighted ? RunwayTerminal.body : .clear)
            )
            .contentShape(RoundedRectangle(cornerRadius: 5))
        }
        .buttonStyle(.plain)
        .pointerCursor()
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: highlighted)
        .help(edge == .above
            ? "\(count) more above. Click or scroll to slide up one card."
            : "\(count) more below. Click or scroll to slide down one card.")
    }

    private var highlighted: Bool { hovering || isDropTarget }
}

/// Catches scroll-wheel and trackpad input over the Focus lane and turns it
/// into whole-card steps through `FocusReelScrollStepper`. A local event
/// monitor rather than a hit-testable view, so the cards above it keep every
/// click, hover and drag.
struct FocusReelScrollCatcher: NSViewRepresentable {
    var isEnabled: Bool
    var onStep: (Int) -> Void

    func makeNSView(context: Context) -> CatcherView {
        let view = CatcherView()
        view.isEnabled = isEnabled
        view.onStep = onStep
        return view
    }

    func updateNSView(_ view: CatcherView, context: Context) {
        view.isEnabled = isEnabled
        view.onStep = onStep
    }

    static func dismantleNSView(_ view: CatcherView, coordinator: ()) {
        view.stopMonitoring()
    }

    final class CatcherView: NSView {
        var isEnabled = true
        var onStep: ((Int) -> Void)?
        private var monitor: Any?
        private var stepper = FocusReelScrollStepper()

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window == nil { stopMonitoring() } else { startMonitoring() }
        }

        private func startMonitoring() {
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                // Local event monitors fire on the main thread.
                nonisolated(unsafe) let ev = event
                let consumed: Bool = MainActor.assumeIsolated {
                    self?.handle(ev) ?? false
                }
                return consumed ? nil : event
            }
        }

        func stopMonitoring() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }

        private func handle(_ event: NSEvent) -> Bool {
            guard isEnabled, let window, event.window === window,
                  !isHiddenOrHasHiddenAncestor,
                  bounds.contains(convert(event.locationInWindow, from: nil)) else { return false }
            let step = stepper.step(
                deltaY: Double(event.scrollingDeltaY),
                precise: event.hasPreciseScrollingDeltas,
                isMomentum: !event.momentumPhase.isEmpty,
                gestureBegan: event.phase.contains(.began),
                timestamp: event.timestamp
            )
            if step != 0 { onStep?(step) }
            return true
        }
    }
}
