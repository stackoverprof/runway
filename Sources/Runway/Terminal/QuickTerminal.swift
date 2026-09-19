import SwiftUI
import AppKit
import GhosttyKit
import UniformTypeIdentifiers

/// A persistent "quick" terminal overlaid on the bottom-left of the left pane.
/// Toggled with ⌘⌥Q or by hovering/peeking the bottom-left corner of the window.
/// It stays mounted while hidden (shid-off/shrunk) so its shell keeps running.
struct QuickTerminal: View {
    static let quickBoxID = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!

    @Bindable var ws: Workspace
    let width: CGFloat            // left-pane width
    let availableHeight: CGFloat  // full pane height
    let resizePane: (CGFloat) -> Void

    @State private var session: GhosttyTerminalSession = makeRunwaySession(QuickTerminal.startupConfig())
    @State private var dragStartHeight: CGFloat?
    @State private var dragStartPaneWidth: CGFloat?
    @State private var isHovered = false
    @State private var hideTask: Task<Void, Never>? = nil
    @State private var allowExpandOnHover = true
    @State private var isPulsing = false
    @State private var shimmerOffset: CGFloat = -0.8
    @State private var pulseTask: Task<Void, Never>? = nil
    @State private var isHoveringHeader = false

    /// The quick terminal runs the configured command on launch, through the
    /// same environment the right-pane terminals get: identical control paths,
    /// wrapper-resolved autorun, and a bound conversation. Hand-rolling this
    /// env is what previously left the quick panel outside Runway's `claude`
    /// wrapper, so it never kept a session.
    static func startupConfig() -> TerminalConfig {
        let command = AgentControl.preferredAgentCommand(
            fallback: SettingsKey.configuredAgentCommand,
            quickTerminalSession: true
        )
        let env = AgentControl.environment(
            for: quickBoxID,
            autorun: command,
            quickTerminalSession: true
        )

        // A folder picked in Settings wins; otherwise reopen where the last
        // shell was left, and fall back to the shell's own default.
        let recordedCwd = (try? Data(contentsOf: AgentControl.cwdFile(for: quickBoxID)))
            .flatMap { String(data: $0, encoding: .utf8) }?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let lastDirectory = (recordedCwd?.isEmpty == false) ? recordedCwd : nil

        return TerminalConfig(
            workingDirectory: QuickTerminalDirectory.startupPath ?? lastDirectory,
            environment: env
        )
    }

    /// Abandon the kept conversation and spawn a fresh shell on a new id. The
    /// only way the quick terminal ever starts over: quitting Runway, switching
    /// repositories, and rebuilding all resume what was there.
    private func startNewSession() {
        QuickTerminalSession.rotate()
        try? FileManager.default.removeItem(at: AgentControl.sessionFile(for: Self.quickBoxID))
        session = makeRunwaySession(Self.startupConfig())
        bindSession()
        applyRunwayTheme(to: session)
    }

    /// Point the workspace's quick-terminal hooks at the mounted session. Must
    /// re-run after a respawn or they keep driving the dead shell.
    private func bindSession() {
        let session = session
        ws.focusQuick = { session.view?.window?.makeFirstResponder(session.view) }
        ws.quickHasKeyboard = {
            guard let view = session.view, let window = view.window else {
                return false
            }
            return window.firstResponder === view
        }
    }

    private let margin: CGFloat = 8
    private let minHeight: CGFloat = 140

    /// Keep a maximized quick terminal below the window controls. The overlay is
    /// bottom-anchored and its outer padding already accounts for both margins.
    private var maxHeight: CGFloat {
        let windowControlsClearance: CGFloat = ws.isFullScreen ? 0 : 44
        return max(minHeight, availableHeight - margin * 2 - windowControlsClearance)
    }

    private var height: CGFloat {
        let fallback = availableHeight * 0.5
        let h = ws.quickHeight == 0 ? fallback : ws.quickHeight
        return min(max(h, minHeight), maxHeight)
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
            // Keep the Ghostty view permanently mounted in the ZStack.
            // When hidden, we set opacity to 0 and disable hit-testing.
            // This prevents the Metal GPU renderer from locking up due to nil window context.
            VStack(spacing: 0) {
                header
                GhosttyTerminalRepresentable(session: session, configuration: .default)
                    .id(ObjectIdentifier(session))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.horizontal, 5)
                    .padding(.bottom, 5)
                    .onAppear {
                        applyRunwayTheme(to: session)
                        bindSession()
                        Task { @MainActor in
                            for _ in 0..<100 {
                                if let view = session.view {
                                    for delay in [0.05, 0.15, 0.35, 0.75, 1.5, 3.0] {
                                        try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                                        if view.window != nil {
                                            forceTerminalLayoutUpdate(for: session)
                                        }
                                    }
                                    break
                                }
                                try? await Task.sleep(nanoseconds: 50_000_000)
                            }
                        }
                    }
                    .onReceive(NotificationCenter.default.publisher(for: NSWindow.didMoveNotification)) { _ in
                        forceTerminalLayoutUpdate(for: session)
                    }
                    .onReceive(NotificationCenter.default.publisher(for: NSWindow.didChangeScreenNotification)) { _ in
                        forceTerminalLayoutUpdate(for: session)
                    }
                    .onReceive(NotificationCenter.default.publisher(for: NSWindow.didChangeBackingPropertiesNotification)) { _ in
                        forceTerminalLayoutUpdate(for: session)
                    }
            }
            .opacity(ws.quickVisible ? 1 : 0)
            .allowsHitTesting(ws.quickVisible)
            
            if !ws.quickVisible {
                // Centered peeking bolt icon when closed
                Image(systemName: "bolt.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color(red: 0.45, green: 0.82, blue: 0.78))
                    .shadow(color: Color(red: 0.45, green: 0.82, blue: 0.78).opacity(0.8), radius: 6)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .pointerCursor()
                    .onTapGesture {
                        ws.quickVisible = true
                    }
                    .transition(.identity)
            }
        }
        .frame(
            width: ws.quickVisible ? actualWidth : 36,
            height: ws.quickVisible ? height : 36
        )
        .background(
            Group {
                if ws.quickVisible {
                    RunwayTerminal.body
                } else {
                    Color.black.opacity(0.55)
                        .background(.ultraThinMaterial)
                }
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(ws.quickVisible ? Color.white.opacity(0.12) : Color.white.opacity(0.15), lineWidth: 1)
        )
        // Invisible drag strip on the top edge to resize when visible.
        .overlay(alignment: .top) {
            if ws.quickVisible { resizeHandle }
        }
        // Dragging the panel's right edge also moves the main split divider,
        // keeping the Quick Terminal edge and pane edge directly connected.
        .overlay(alignment: .trailing) {
            if ws.quickVisible { resizePaneHandle }
        }
        // The top-right corner is the combined resize affordance: diagonal
        // drags change the Quick Terminal height and the left/right split.
        .overlay(alignment: .topTrailing) {
            if ws.quickVisible { combinedResizeHandle }
        }
        .shadow(color: .black.opacity(ws.quickVisible ? 0.55 : 0.25), radius: ws.quickVisible ? 18 : 6, y: ws.quickVisible ? 8 : 2)
        .onDrop(of: [.fileURL, .image], isTargeted: nil) { providers in
            guard ws.quickVisible else { return false }
            handleDropProviders(providers, session: session)
            return true
        }
        .padding(margin)
        .animation(.spring(response: 0.35, dampingFraction: 0.82), value: ws.quickVisible)
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovered = hovering
            if hovering {
                hideTask?.cancel()
                hideTask = nil
            } else {
                allowExpandOnHover = true // Reset allowed state when mouse leaves
                triggerAutoHide()
            }
        }
        .onChange(of: ws.quickVisible) { _, visible in
            if !visible {
                allowExpandOnHover = false // Require mouse exit before next expand
            }
            DispatchQueue.main.async {
                if visible {
                    if let view = session.view { view.window?.makeFirstResponder(view) }
                } else {
                    TerminalRegistry.shared.focusTerminal(ws.focusedID)
                }
            }
        }
        .onChange(of: ws.focusedID) { _, _ in
            if !isHovered {
                triggerAutoHide()
            }
        }
        .onChange(of: ws.quickState) { old, new in
            if new == .needsAction {
                pulseTask?.cancel()
                shimmerOffset = -0.8
                pulseTask = Task {
                    withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                        shimmerOffset = 1.0
                    }
                    try? await Task.sleep(nanoseconds: 3_000_000_000)
                    guard !Task.isCancelled else { return }
                    withAnimation(.easeInOut(duration: 0.3)) {
                        isPulsing = false
                        shimmerOffset = -0.8
                    }
                    
                    // Then hide on the configured schedule, unless it is
                    // pinned, hovered, focused, or auto-hide is off.
                    try? await Task.sleep(
                        nanoseconds: UInt64(SettingsKey.quickAutoHideDelay() * 1_000_000_000)
                    )
                    guard !Task.isCancelled else { return }
                    guard SettingsKey.quickAutoHideEnabled() else { return }
                    guard !isHovered else { return }
                    guard !isFocused else { return }
                    guard !ws.quickPinned else { return }
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                        ws.quickVisible = false
                    }
                }
                withAnimation(.easeInOut(duration: 0.3)) {
                    isPulsing = true
                }
            } else {
                pulseTask?.cancel()
                withAnimation(.easeInOut(duration: 0.3)) {
                    isPulsing = false
                    shimmerOffset = -0.8
                }
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

            if isHoveringHeader {
                Button {
                    startNewSession()
                } label: {
                    Image(systemName: "plus.bubble")
                        .font(.system(size: 10.5))
                        .foregroundStyle(Color.white.opacity(0.4))
                }
                .buttonStyle(.plain)
                .pointerCursor()
                .help("Start a new agent session, abandoning the kept conversation")
            }

            // Pin button (only show on hover or when pinned)
            if isHoveringHeader || ws.quickPinned {
                Button {
                    ws.quickPinned.toggle()
                } label: {
                    Image(systemName: ws.quickPinned ? "pin.fill" : "pin")
                        .font(.system(size: 10.5))
                        .foregroundStyle(ws.quickPinned ? Color(red: 0.45, green: 0.82, blue: 0.78) : Color.white.opacity(0.4))
                }
                .buttonStyle(.plain)
                .pointerCursor()
                .help(ws.quickPinned ? "Unpin to auto-hide" : "Pin to stay open")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .onHover { hovering in
            isHoveringHeader = hovering
        }
        .background(
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RunwayTerminal.headerBar
                    if isPulsing {
                        LinearGradient(
                            gradient: Gradient(colors: [
                                Color.clear,
                                Color(red: 0.91, green: 0.62, blue: 0.20).opacity(0.10),
                                Color.clear
                            ]),
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .frame(width: geo.size.width * 0.8)
                        .offset(x: geo.size.width * shimmerOffset)
                    }
                }
            }
        )
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
                        ws.quickHeight = min(max(base - value.translation.height, minHeight), maxHeight)
                    }
                    .onEnded { _ in dragStartHeight = nil }
            )
    }

    /// The panel fills the left pane, so resizing its trailing edge resizes
    /// both together. ContentView applies the same pane min/max limits as the
    /// main divider. Keep the header clear so its buttons remain clickable.
    private var resizePaneHandle: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: 32)
            Color.clear
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .onHover { hovering in
                    if hovering { NSCursor.resizeLeftRight.set() } else { NSCursor.arrow.set() }
                }
                .highPriorityGesture(
                    DragGesture(coordinateSpace: .global)
                        .onChanged { value in
                            if dragStartPaneWidth == nil { dragStartPaneWidth = width }
                            let base = dragStartPaneWidth ?? width
                            resizePane(base + value.translation.width)
                        }
                        .onEnded { _ in dragStartPaneWidth = nil }
                )
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .frame(width: 14)
    }

    private var combinedResizeHandle: some View {
        Color.clear
        // Stay inside the clear corner beyond the header's 12pt content inset,
        // so the resize hit target never covers the header buttons.
        .frame(width: 12, height: 12)
        .contentShape(Rectangle())
        .onHover { hovering in
            if hovering {
                diagonalResizeCursor.set()
            } else {
                NSCursor.arrow.set()
            }
        }
        .highPriorityGesture(
            DragGesture(coordinateSpace: .global)
                .onChanged { value in
                    if dragStartHeight == nil { dragStartHeight = height }
                    if dragStartPaneWidth == nil { dragStartPaneWidth = width }

                    let baseHeight = dragStartHeight ?? height
                    let baseWidth = dragStartPaneWidth ?? width
                    ws.quickHeight = min(
                        max(baseHeight - value.translation.height, minHeight),
                        maxHeight
                    )
                    resizePane(baseWidth + value.translation.width)
                }
                .onEnded { _ in
                    dragStartHeight = nil
                    dragStartPaneWidth = nil
                }
        )
    }

    private var diagonalResizeCursor: NSCursor {
        if #available(macOS 15.0, *) {
            return .frameResize(position: .topRight, directions: .all)
        }
        let image = NSImage(
            systemSymbolName: "arrow.up.left.and.arrow.down.right",
            accessibilityDescription: "Resize diagonally"
        ) ?? NSImage(size: NSSize(width: 16, height: 16))
        return NSCursor(image: image, hotSpot: NSPoint(x: 8, y: 8))
    }


    private func triggerAutoHide() {
        guard !ws.quickPinned else { return }
        guard SettingsKey.quickAutoHideEnabled() else { return }

        hideTask?.cancel()
        let delay = SettingsKey.quickAutoHideDelay()
        hideTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            guard !isHovered else { return }
            guard !isFocused else { return }
            guard !ws.quickPinned else { return }
            
            ws.quickVisible = false
        }
    }
}
