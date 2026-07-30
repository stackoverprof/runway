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
            let n = ws.boxes.count
            ZStack {
                VStack(spacing: ws.soloed ? 0 : 12) {
                    ForEach($ws.boxes) { $box in
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
                            fixedHeight: fixedHeight(for: box, geo: geo, count: n)
                        )
                        .id(box.id)
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

                if ws.focusBoardControlsBoxes && ws.boxes.isEmpty {
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
        .animation(.easeInOut(duration: 0.2), value: ws.boxes.map(\.id))
        .task(id: ws.focusBoardControlsBoxes && ws.boxes.isEmpty) {
            guard ws.focusBoardControlsBoxes, ws.boxes.isEmpty else { return }
            emptyStateIndex = Int.random(in: 0..<Self.emptyStates.count)
            emptyStateOpacity = 1

            while !Task.isCancelled {
                do {
                    try await Task.sleep(nanoseconds: 15_000_000_000)
                } catch {
                    return
                }
                guard !Task.isCancelled, ws.boxes.isEmpty else { return }

                withAnimation(.easeInOut(duration: 0.18)) {
                    emptyStateOpacity = 0
                }
                do {
                    try await Task.sleep(nanoseconds: 220_000_000)
                } catch {
                    return
                }
                guard !Task.isCancelled, ws.boxes.isEmpty else { return }

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
        if let fid = ws.focusedID, ws.boxes.contains(where: { $0.id == fid }) {
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
