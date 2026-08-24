import SwiftUI

struct RightPane: View {
    @Bindable var ws: Workspace
    @State private var emptyStateIndex = Int.random(in: 0..<8)
    @State private var emptyStateOpacity = 1.0

    private static let emptyStates: [(icon: String, message: String)] = [
        ("beach.umbrella", "Nothing in focus today. Take it easy."),
        ("ladybug", "Ready to squash a few bugs?"),
        ("bolt", "Ready to kick off something new?"),
        ("scope", "Pick a target and bring it into focus."),
        ("cup.and.saucer", "No mission yet. Coffee first?"),
        ("flag.checkered", "What are we shipping next?"),
        ("checkmark.circle", "All clear. Enjoy the quiet."),
        ("sparkles", "A clean slate. What should we move first?"),
    ]

    var body: some View {
        GeometryReader { geo in
            let activeBoxes = ws.activeBoxes
            let activeIDs = Set(activeBoxes.map(\.id))
            let n = activeBoxes.count
            let axis = ws.terminalLayoutAxis
            ZStack {
                PersistentTerminalLayout(spacing: ws.soloed ? 0 : 12, axis: axis) {
                    ForEach($ws.boxes) { $box in
                        let isActive = activeIDs.contains(box.id)
                        let presentation = TerminalPresentationPolicy.state(
                            isActiveRepository: isActive,
                            isSoloed: ws.soloed,
                            isFocused: box.id == ws.focusedID
                        )
                        ResizableBox(
                            id: box.id,
                            workspace: ws,
                            name: $box.name,
                            detail: $box.detail,
                            state: box.state,
                            config: TerminalConfig(
                                workingDirectory: box.cwd,
                                environment: AgentControl.environment(
                                    for: box.id,
                                    autorun: box.autorun,
                                    focusRepository: box.focusRepository,
                                    focusIssueNumber: box.focusIssueNumber,
                                    issueAgentSessionsEnabled: UserDefaults.standard.bool(
                                        forKey: SettingsKey.issueAgentSessionsEnabled
                                    )
                                )
                            ),
                            height: $box.height,
                            isFocused: ws.focusedID == box.id,
                            isFocusManaged: box.focusIssueNumber != nil,
                            focusIssueNumber: box.focusIssueNumber,
                            focusRepository: box.focusRepository,
                            // Parked boxes (other repositories) stay 1×1 whatever
                            // the axis; the presented ones accordion along it.
                            fixedHeight: presentation.isInLayout
                                ? (axis == .horizontal
                                    ? nil
                                    : fixedSpan(for: box, geo: geo, count: n))
                                : 1,
                            fixedWidth: presentation.isInLayout && axis == .horizontal
                                ? fixedSpan(for: box, geo: geo, count: n)
                                : nil
                        )
                        .id(box.id)
                        // Active-repository terminals stay in the vertical layout
                        // during Focus navigation. Their heights accordion between
                        // zero and full size, preserving the switch direction like
                        // v1. Only other repositories are parked at 1×1.
                        .opacity(presentation.isInLayout ? 1 : 0)
                        .allowsHitTesting(presentation.isInteractive)
                        .accessibilityHidden(!presentation.isInteractive)
                        .layoutValue(
                            key: TerminalPresentedLayoutValueKey.self,
                            value: presentation.isInLayout
                        )
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

                if ws.focusBoardControlsBoxes && activeBoxes.isEmpty {
                    focusEmptyState
                    hint
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 16)
                }
            }
        }
        .background(Color.black)
        .animation(.easeInOut(duration: 0.2), value: ws.soloed)
        .animation(.easeInOut(duration: 0.2), value: ws.focusedID)
        .animation(.easeInOut(duration: 0.2), value: ws.activeBoxes.map(\.id))
        .task(id: ws.focusBoardControlsBoxes && ws.activeBoxes.isEmpty) {
            guard ws.focusBoardControlsBoxes, ws.activeBoxes.isEmpty else { return }
            emptyStateIndex = Int.random(in: 0..<Self.emptyStates.count)
            emptyStateOpacity = 1

            while !Task.isCancelled {
                do {
                    try await Task.sleep(nanoseconds: 15_000_000_000)
                } catch {
                    return
                }
                guard !Task.isCancelled, ws.activeBoxes.isEmpty else { return }

                withAnimation(.easeInOut(duration: 0.18)) {
                    emptyStateOpacity = 0
                }
                do {
                    try await Task.sleep(nanoseconds: 220_000_000)
                } catch {
                    return
                }
                guard !Task.isCancelled, ws.activeBoxes.isEmpty else { return }

                var nextIndex = Int.random(in: 0..<Self.emptyStates.count)
                while nextIndex == emptyStateIndex {
                    nextIndex = Int.random(in: 0..<Self.emptyStates.count)
                }
                emptyStateIndex = nextIndex
                withAnimation(.easeInOut(duration: 0.22)) {
                    emptyStateOpacity = 1
                }
            }
        }
    }

    /// A box's share along the accordion axis: pane height when stacking
    /// vertically, pane width when laying out columns. Solo fills the pane with
    /// one terminal either way.
    private func fixedSpan(for box: AgentBox, geo: GeometryProxy, count n: Int) -> CGFloat {
        let paneSpan = ws.terminalLayoutAxis == .horizontal
            ? geo.size.width
            : geo.size.height
        let isFocusedBoxActive = ws.focusedID.map { id in
            ws.activeBoxes.contains { $0.id == id }
        } ?? false
        return AccordionSpanPolicy.span(
            isFocused: box.id == ws.focusedID,
            focusedIsActive: isFocusedBoxActive,
            soloed: ws.soloed,
            paneSpan: paneSpan,
            count: n,
            minimumSpan: ws.terminalLayoutAxis == .horizontal ? 120 : 50
        )
    }

    private var hint: some View {
        VStack(spacing: 3) {
            Text("⌘⌥↑↓ navigate  ·  ⌘1–9 jump  ·  ⌘⌥⏎ focus")
            Text("⌘⌥Q quick terminal  ·  ⌘⌥←→ switch terminal")
        }
        .font(.system(size: 10.5, design: .monospaced))
        .foregroundStyle(Color.white.opacity(0.2))
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity, alignment: .center)
        .allowsHitTesting(false)
    }

    private var focusEmptyState: some View {
        let state = Self.emptyStates[emptyStateIndex]
        return VStack(spacing: 10) {
            Image(systemName: state.icon)
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(Color.white.opacity(0.26))
            Text(state.message)
                .font(.system(size: 10.5, weight: .regular, design: .monospaced))
                .foregroundStyle(Color.white.opacity(0.30))
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity)
        .opacity(emptyStateOpacity)
        .allowsHitTesting(false)
    }
}

/// The weighted accordion split, axis-agnostic: the same numbers size heights in
/// the vertical stack and widths in the horizontal one.
enum AccordionSpanPolicy {
    /// 16pt pane padding on each side; 12pt gaps between presented boxes.
    static func span(
        isFocused: Bool,
        focusedIsActive: Bool,
        soloed: Bool,
        paneSpan: CGFloat,
        count n: Int,
        minimumSpan: CGFloat
    ) -> CGFloat {
        if soloed {
            return isFocused ? max(paneSpan - 32, 60) : 0
        }
        guard n > 0 else { return paneSpan }
        let available = max(paneSpan - 32 - 12 * CGFloat(max(0, n - 1)),
                            CGFloat(n) * minimumSpan)
        if focusedIsActive {
            let total = CGFloat(n + 1)   // focused weight 2, others 1
            return isFocused ? available * 2 / total : available / total
        }
        return available / CGFloat(n)
    }
}

struct TerminalPresentationState: Equatable {
    let isInLayout: Bool
    let isInteractive: Bool
}

enum TerminalPresentationPolicy {
    static func state(
        isActiveRepository: Bool,
        isSoloed: Bool,
        isFocused: Bool
    ) -> TerminalPresentationState {
        TerminalPresentationState(
            isInLayout: isActiveRepository,
            isInteractive: isActiveRepository && (!isSoloed || isFocused)
        )
    }
}

private struct TerminalPresentedLayoutValueKey: LayoutValueKey {
    static let defaultValue = true
}

/// Keeps every terminal surface mounted while laying out only the selected
/// repository's boxes. Hidden terminals share a 1×1 parking spot and continue
/// running without consuming visible pane space.
private struct PersistentTerminalLayout: Layout {
    let spacing: CGFloat
    let axis: TerminalLayoutAxis

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        CGSize(width: proposal.width ?? 0, height: proposal.height ?? 0)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        var offset = axis == .horizontal ? bounds.minX : bounds.minY
        for subview in subviews {
            guard subview[TerminalPresentedLayoutValueKey.self] else {
                subview.place(
                    at: CGPoint(x: bounds.minX, y: bounds.minY),
                    anchor: .topLeading,
                    proposal: ProposedViewSize(width: 1, height: 1)
                )
                continue
            }

            switch axis {
            case .vertical:
                let size = subview.sizeThatFits(
                    ProposedViewSize(width: bounds.width, height: nil)
                )
                subview.place(
                    at: CGPoint(x: bounds.minX, y: offset),
                    anchor: .topLeading,
                    proposal: ProposedViewSize(width: bounds.width, height: size.height)
                )
                offset += size.height + spacing
            case .horizontal:
                let size = subview.sizeThatFits(
                    ProposedViewSize(width: nil, height: bounds.height)
                )
                subview.place(
                    at: CGPoint(x: offset, y: bounds.minY),
                    anchor: .topLeading,
                    proposal: ProposedViewSize(width: size.width, height: bounds.height)
                )
                offset += size.width + spacing
            }
        }
    }
}
