import SwiftUI
import AppKit
import GhosttyKit

/// A persistent "quick" terminal overlaid on the bottom-left of the left pane.
/// Toggled with ⌘⌥Q or by hovering/peeking the bottom-left corner of the window.
/// It stays mounted while hidden (slid off-screen) so its shell keeps running.
struct QuickTerminal: View {
    @Bindable var ws: Workspace
    let width: CGFloat            // left-pane width
    let availableHeight: CGFloat  // full pane height

    @State private var session: GhosttyTerminalSession = makeRunwaySession(QuickTerminal.startupConfig())
    @State private var dragStartHeight: CGFloat?
    @State private var isHovered = false
    @State private var hideTask: Task<Void, Never>? = nil

    /// The quick terminal also runs the configured command on launch (it uses the
    /// Runway ZDOTDIR so the .zshrc autorun block fires).
    static func startupConfig() -> TerminalConfig {
        let cmd = (UserDefaults.standard.string(forKey: SettingsKey.initialCommand) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        var env = [
            "ZDOTDIR": AgentControl.zdotdir.path,
            "RUNWAY_FEED": AgentControl.feedInbox.path,
        ]
        if !cmd.isEmpty { env["RUNWAY_AUTORUN"] = cmd }
        return TerminalConfig(environment: env)
    }

    private let margin: CGFloat = 8
    private let minHeight: CGFloat = 140
    private let peekSize: CGFloat = 36

    private var height: CGFloat {
        let fallback = availableHeight * 0.5
        let h = ws.quickHeight == 0 ? fallback : ws.quickHeight
        return min(max(h, minHeight), availableHeight - margin * 2)
    }

    private var actualWidth: CGFloat {
        max(width - margin * 2, 120)
    }

    private var isFocused: Bool {
        if let view = session.view, let window = view.window {
            return window.firstResponder == view
        }
        return false
    }

    var body: some View {
        ZStack {
            if ws.quickVisible {
                VStack(spacing: 0) {
                    header
                    GhosttyTerminalRepresentable(session: session, configuration: .default)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(.horizontal, 5)
                        .padding(.bottom, 5)
                        .onAppear {
                            applyRunwayTheme(to: session)
                            ws.focusQuick = { session.view?.window?.makeFirstResponder(session.view) }
                        }
                        .dropDestination(for: URL.self) { urls, _ in
                            let text = urls.map { runwayShellEscape($0.path) }.joined(separator: " ")
                            guard !text.isEmpty else { return false }
                            session.insertText(text + " ")
                            return true
                        }
                }
                .transition(.identity)
            } else {
                // Diagonal bottom-left corner peek tab
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Color(red: 0.45, green: 0.82, blue: 0.78))
                            .shadow(color: Color(red: 0.45, green: 0.82, blue: 0.78).opacity(0.8), radius: 6)
                    }
                }
                .padding(10)
                .frame(width: actualWidth, height: height, alignment: .bottomTrailing)
                .transition(.identity)
            }
        }
        .frame(width: actualWidth, height: height)
        .background(ws.quickVisible ? RunwayTerminal.body : Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(ws.quickVisible ? Color.white.opacity(0.12) : Color.white.opacity(0.08), lineWidth: 1)
        )
        // Invisible drag strip on the top edge to resize when visible.
        .overlay(alignment: .top) {
            if ws.quickVisible { resizeHandle }
        }
        .shadow(color: .black.opacity(ws.quickVisible ? 0.55 : 0.2), radius: ws.quickVisible ? 18 : 6, y: ws.quickVisible ? 8 : 2)
        .padding(margin)
        // Slide diagonally off the bottom-left (so only the bottom-right corner of the view remains at bottom-left of the window)
        .offset(
            x: ws.quickVisible ? 0 : -actualWidth + peekSize,
            y: ws.quickVisible ? 0 : height - peekSize
        )
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovered = hovering
            if hovering {
                hideTask?.cancel()
                hideTask = nil
                
                // Auto-expand on corner hover
                if !ws.quickVisible {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                        ws.quickVisible = true
                    }
                }
            } else {
                triggerAutoHide()
            }
        }
        .onChange(of: ws.quickVisible) { _, visible in
            DispatchQueue.main.async {
                if visible {
                    if let view = session.view { view.window?.makeFirstResponder(view) }
                } else {
                    TerminalRegistry.shared.focusTerminal(ws.focusedID)
                }
            }
        }
        .onChange(of: ws.focusedID) { _, _ in
            // If focus shifts away and mouse is not hovering, trigger auto-hide
            if !isHovered {
                triggerAutoHide()
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
            
            // Pin button
            Button {
                ws.quickPinned.toggle()
            } label: {
                Image(systemName: ws.quickPinned ? "pin.fill" : "pin")
                    .font(.system(size: 10.5))
                    .foregroundStyle(ws.quickPinned ? Color(red: 0.45, green: 0.82, blue: 0.78) : Color.white.opacity(0.4))
            }
            .buttonStyle(.plain)
            .help(ws.quickPinned ? "Unpin to auto-hide" : "Pin to stay open")
            
            Text("⌘⌥Q")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(Color.white.opacity(0.25))
                .padding(.leading, 4)
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

    private func triggerAutoHide() {
        guard !ws.quickPinned else { return }
        guard !isFocused else { return }
        
        hideTask?.cancel()
        hideTask = Task {
            try? await Task.sleep(nanoseconds: 800_000_000) // 0.8s delay
            guard !Task.isCancelled else { return }
            guard !isHovered else { return }
            guard !isFocused else { return }
            guard !ws.quickPinned else { return }
            
            withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                ws.quickVisible = false
            }
        }
    }
}
