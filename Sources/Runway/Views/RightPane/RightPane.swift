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
            ZStack {
                PersistentTerminalLayout(spacing: ws.soloed ? 0 : 12) {
                    ForEach($ws.boxes) { $box in
                        let isActive = activeIDs.contains(box.id)
                        let isPresented = isActive
                            && (!ws.soloed || box.id == ws.focusedID)
                        ResizableBox(
                            id: box.id,
                            workspace: ws,
                            name: $box.name,
                            detail: $box.detail,
                            state: box.state,
                            config: TerminalConfig(workingDirectory: box.cwd,
                                                   environment: AgentControl.environment(for: box.id, autorun: box.autorun)),
                            height: $box.height,
                            isFocused: ws.focusedID == box.id,
                            isFocusManaged: box.focusIssueNumber != nil,
                            focusIssueNumber: box.focusIssueNumber,
                            fixedHeight: isPresented
                                ? fixedHeight(for: box, geo: geo, count: n)
                                : 1
                        )
                        .id(box.id)
                        .opacity(isPresented ? 1 : 0)
                        .allowsHitTesting(isPresented)
                        .accessibilityHidden(!isPresented)
                        .layoutValue(
                            key: TerminalPresentedLayoutValueKey.self,
                            value: isPresented
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

    /// Solo fills the pane with one terminal. Otherwise terminals always use the
    /// weighted accordion split.
    private func fixedHeight(for box: AgentBox, geo: GeometryProxy, count n: Int) -> CGFloat {
        if ws.soloed {
            return box.id == ws.focusedID ? max(geo.size.height - 32, 60) : 0
        }
        let available = max(geo.size.height - 32 - 12 * CGFloat(max(0, n - 1)),
                            CGFloat(n) * 50)
        return accordionHeight(for: box, available: available, count: n)
    }

    /// Equal split, or—if a box is focused—weight the focused box 2× the others.
    private func accordionHeight(for box: AgentBox, available: CGFloat, count n: Int) -> CGFloat {
        guard n > 0 else { return available }
        if let fid = ws.focusedID, ws.activeBoxes.contains(where: { $0.id == fid }) {
            let total = CGFloat(n + 1)   // focused weight 2, others 1
            return box.id == fid ? available * 2 / total : available / total
        }
        return available / CGFloat(n)
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

private struct TerminalPresentedLayoutValueKey: LayoutValueKey {
    static let defaultValue = true
}

/// Keeps every terminal surface mounted while laying out only the selected
/// repository's boxes. Hidden terminals share a 1×1 parking spot and continue
/// running without consuming visible pane space.
private struct PersistentTerminalLayout: Layout {
    let spacing: CGFloat

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
        var y = bounds.minY
        for subview in subviews {
            guard subview[TerminalPresentedLayoutValueKey.self] else {
                subview.place(
                    at: CGPoint(x: bounds.minX, y: bounds.minY),
                    anchor: .topLeading,
                    proposal: ProposedViewSize(width: 1, height: 1)
                )
                continue
            }

            let size = subview.sizeThatFits(
                ProposedViewSize(width: bounds.width, height: nil)
            )
            subview.place(
                at: CGPoint(x: bounds.minX, y: y),
                anchor: .topLeading,
                proposal: ProposedViewSize(width: bounds.width, height: size.height)
            )
            y += size.height + spacing
        }
    }
}
