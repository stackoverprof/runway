import SwiftUI

struct RightPane: View {
    @Bindable var ws: Workspace

    var body: some View {
        GeometryReader { geo in
            let n = ws.boxes.count
            // One ScrollView for all modes so terminal sessions keep their
            // identity (toggling modes must not respawn the shells).
            ScrollViewReader { proxy in
                ScrollView {
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
                                fixedHeight: fixedHeight(for: box, geo: geo, count: n)
                            )
                            .id(box.id)
                        }
                        if !ws.accordion && !ws.soloed {
                            addButton
                            hint
                        }
                    }
                    .padding(16)
                    .frame(minHeight: (ws.accordion || ws.soloed) ? geo.size.height : nil,
                           alignment: .top)
                }
                .ignoresSafeArea()
                .scrollDisabled(ws.accordion || ws.soloed)
                .scrollIndicators(.hidden)
                .onChange(of: ws.focusedID) { _, id in
                    guard let id else { return }
                    withAnimation(.easeInOut(duration: 0.2)) { proxy.scrollTo(id, anchor: .center) }
                }
            }
        }
        .background(Color.black)
        .animation(.easeInOut(duration: 0.2), value: ws.accordion)
        .animation(.easeInOut(duration: 0.2), value: ws.soloed)
        .animation(.easeInOut(duration: 0.2), value: ws.focusedID)
    }

    /// Per-box height: solo → only focused fills, others collapse; accordion →
    /// weighted split; normal → nil (the box uses its own resizable height).
    private func fixedHeight(for box: AgentBox, geo: GeometryProxy, count n: Int) -> CGFloat? {
        if ws.soloed {
            return box.id == ws.focusedID ? max(geo.size.height - 32, 60) : 0
        }
        if ws.accordion {
            let available = max(geo.size.height - 32 - 12 * CGFloat(max(0, n - 1)),
                                CGFloat(n) * 50)
            return accordionHeight(for: box, available: available, count: n)
        }
        return nil
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

    private var addButton: some View {
        Button {
            ws.newBox()
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.55))
                .frame(maxWidth: .infinity)
                .frame(height: 40)
                .background(RoundedRectangle(cornerRadius: 9).fill(Color(white: 0.05)))
                .overlay(
                    RoundedRectangle(cornerRadius: 9)
                        .strokeBorder(Color.white.opacity(0.10),
                                      style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            if hovering { NSCursor.pointingHand.set() } else { NSCursor.arrow.set() }
        }
        .help("Add agent")
    }

    private var hint: some View {
        VStack(spacing: 3) {
            Text("⌘N add  ·  ⌘W close  ·  ⌘⌥↑↓ navigate  ·  ⌘⌥⇧↑↓ reorder  ·  ⌘1–9 jump")
            Text("⌘⌥⏎ solo  ·  ⌘⌥A accordion  ·  ⌘⌥Q quick terminal  ·  ⌘+scroll to scroll")
        }
        .font(.system(size: 10.5, design: .monospaced))
        .foregroundStyle(Color.white.opacity(0.2))
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.top, 6)
    }
}
