import SwiftUI
import AppKit
import GhosttyKit

/// A persistent "quick" terminal overlaid on the bottom-left of the left pane.
/// Toggled with ⌘⌥Q. It stays mounted while hidden (slid off-screen) so its shell
/// keeps running in the background. Resizable by dragging its top edge.
struct QuickTerminal: View {
    let width: CGFloat            // left-pane width
    let availableHeight: CGFloat  // full pane height

    @Bindable private var ws = Workspace.shared
    @State private var session: GhosttyTerminalSession = makeRunwaySession()
    @State private var dragStartHeight: CGFloat?

    private let margin: CGFloat = 8
    private let minHeight: CGFloat = 140

    private var height: CGFloat {
        let fallback = availableHeight * 0.5
        let h = ws.quickHeight == 0 ? fallback : ws.quickHeight
        return min(max(h, minHeight), availableHeight - margin * 2)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            GhosttyTerminalRepresentable(session: session, configuration: .default)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, 5)
                .padding(.bottom, 5)
                .onAppear { applyRunwayTheme(to: session) }
                .dropDestination(for: URL.self) { urls, _ in
                    let text = urls.map { runwayShellEscape($0.path) }.joined(separator: " ")
                    guard !text.isEmpty else { return false }
                    session.insertText(text + " ")
                    return true
                }
        }
        .frame(width: max(width - margin * 2, 120), height: height)
        .background(RunwayTerminal.body)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.12), lineWidth: 1))
        // Invisible drag strip on the top edge to resize (no visible line above the header).
        .overlay(alignment: .top) { resizeHandle }
        .shadow(color: .black.opacity(0.55), radius: 18, y: 8)
        .padding(margin)
        // Slide off the bottom when hidden; stays mounted so the shell keeps running.
        .offset(y: ws.quickVisible ? 0 : height + margin * 2 + 24)
        .opacity(ws.quickVisible ? 1 : 0)
        .allowsHitTesting(ws.quickVisible)
        .animation(.easeOut(duration: 0.22), value: ws.quickVisible)
        .onChange(of: ws.quickVisible) { _, visible in
            guard visible else { return }
            // Focus the quick terminal so you can type immediately.
            DispatchQueue.main.async {
                if let view = session.view { view.window?.makeFirstResponder(view) }
            }
        }
    }

    private var header: some View {
        HStack(spacing: 7) {
            Image(systemName: "bolt.fill")
                .font(.system(size: 9))
                .foregroundStyle(Color.white.opacity(0.5))
            Text("quick")
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(Color.white.opacity(0.8))
            Spacer()
            Text("⌘⌥Q")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(Color.white.opacity(0.25))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(RunwayTerminal.headerBar)
    }

    /// Drag the top edge to resize (the panel is bottom-anchored, so dragging up
    /// makes it taller). Invisible — just a hit strip.
    private var resizeHandle: some View {
        Color.clear
            .frame(height: 8)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .onHover { hovering in
                if hovering { NSCursor.resizeUpDown.set() } else { NSCursor.arrow.set() }
            }
            .highPriorityGesture(
                DragGesture(coordinateSpace: .global)
                    .onChanged { value in
                        if dragStartHeight == nil { dragStartHeight = height }
                        let base = dragStartHeight ?? height
                        ws.quickHeight = min(max(base - value.translation.height, minHeight),
                                             availableHeight - margin * 2)
                    }
                    .onEnded { _ in dragStartHeight = nil }
            )
    }
}
