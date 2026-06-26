import SwiftUI
import AppKit
import GhosttyKit

@main
struct RunwayApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        // Must run before any terminal (GhosttyKit) loads its config.
        RunwayTerminal.installTheme()
    }

    var body: some Scene {
        WindowGroup("Runway") {
            ContentView()
                .frame(minWidth: 720, minHeight: 480)
                .ignoresSafeArea()
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 1100, height: 720)
    }
}

/// Empty skeleton: a flexible left | right split with a draggable divider.
/// No titlebar/toolbar chrome — content runs edge to edge. Built as a plain
/// HStack (not HSplitView) so it can fill under the hidden titlebar.
struct ContentView: View {
    @Bindable private var ws = Workspace.shared
    private let minLeft: CGFloat = 220
    private let minRight: CGFloat = 320

    var body: some View {
        GeometryReader { geo in
            let total = geo.size.width
            let maxLeft = max(minLeft, total - minRight)
            let left = min(max(ws.leftWidth, minLeft), maxLeft)

            ZStack(alignment: .bottomLeading) {
                HStack(spacing: 0) {
                    LeftPane()                     // GitHub activity feed
                        .frame(width: left)

                    Rectangle()
                        .fill(Color.white.opacity(0.07))
                        .frame(width: 1)
                        .overlay(
                            Rectangle()
                                .fill(.clear)
                                .frame(width: 12)          // wider invisible hit target
                                .contentShape(Rectangle())
                                .onHover { hovering in
                                    if hovering { NSCursor.resizeLeftRight.set() }
                                    else { NSCursor.arrow.set() }
                                }
                                .gesture(
                                    DragGesture(coordinateSpace: .named("split"))
                                        .onChanged { value in
                                            ws.leftWidth = min(max(value.location.x, minLeft), maxLeft)
                                        }
                                )
                        )

                    RightPane()                    // right: scrollable boxes + add button
                        .frame(maxWidth: .infinity)
                }
                .frame(maxHeight: .infinity)
                .coordinateSpace(name: "split")

                // Always mounted (so its shell keeps running); slides in/out with ⌘⌥Q.
                QuickTerminal(width: left, availableHeight: geo.size.height)
            }
        }
        .ignoresSafeArea()
        .background(WindowConfigurator())
    }
}

/// One agent box: an editable name + its own height. Stable `id` so each box's
/// terminal session survives renames, resizes, and adding new boxes.
struct AgentBox: Identifiable, Codable {
    var id = UUID()
    var name: String
    var detail: String = ""
    var state: AgentState = .idle   // runtime only — not persisted
    var height: CGFloat = 264

    enum CodingKeys: String, CodingKey { case id, name, detail, height }
}

/// Right pane: a vertical list of agent boxes. Normal mode scrolls (⌘-scroll);
/// accordion mode (⌘⌥A) locks scrolling and splits the height across boxes, with
/// the focused box getting a larger share.
struct RightPane: View {
    @Bindable private var ws = Workspace.shared

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
                                name: $box.name,
                                detail: $box.detail,
                                state: box.state,
                                config: TerminalConfig(environment: AgentControl.environment(for: box.id)),
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
                .background(RoundedRectangle(cornerRadius: 12).fill(Color(white: 0.05)))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
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

/// An agent card: a green status dot + name on the left, status word on the
/// right, with a live GPU terminal (libghostty) filling the body. Height is
/// resizable via the bottom edge.
private struct ResizableBox: View {
    let id: UUID
    @Binding var name: String
    @Binding var detail: String
    var state: AgentState = .idle
    let config: TerminalConfig
    @Binding var height: CGFloat
    var isFocused: Bool = false
    /// When non-nil (accordion mode) the box uses this height and the resize
    /// handle is disabled.
    var fixedHeight: CGFloat? = nil
    @State private var startHeight: CGFloat?
    @State private var isEditingName = false
    @State private var isEditingDetail = false
    @State private var isHoveringHeader = false

    private let maxDetail = 40

    private let minHeight: CGFloat = 60
    private let maxHeight: CGFloat = 1400
    private let edgeGrab: CGFloat = 10

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .background(RunwayTerminal.headerBar)   // slightly lighter header bar
            TerminalSurfaceView(boxID: id, config: config)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, 5)
                .padding(.bottom, 5)   // small inset keeps the terminal clear of the rounded corners
        }
        .frame(height: fixedHeight ?? height)
        .background(RunwayTerminal.body)                 // darker body fills the inset
        .clipShape(RoundedRectangle(cornerRadius: 12))
        // Focus: a very slight brighter border + faint white glow.
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isFocused ? Color.white.opacity(0.22) : Color.white.opacity(0.07),
                        lineWidth: 1)
        )
        .shadow(color: isFocused ? Color.white.opacity(0.12) : .clear,
                radius: isFocused ? 10 : 0)
        .overlay(alignment: .bottom) {
            if fixedHeight == nil { bottomEdgeHandle }   // no resize in accordion mode
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(state.color)
                .frame(width: 7, height: 7)
                .shadow(color: state.glows ? state.color.opacity(0.9) : .clear, radius: 4)
            nameField
                .layoutPriority(1)
            Spacer(minLength: 8)
            detailField
                .layoutPriority(0)
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onHover { isHoveringHeader = $0 }
        .onTapGesture { Workspace.shared.focusedID = id }
    }

    /// The agent name: a label that becomes an inline text field when clicked.
    @ViewBuilder
    private var nameField: some View {
        if isEditingName {
            InlineField(
                text: $name,
                font: .monospacedSystemFont(ofSize: 13, weight: .medium),
                color: .white,
                onEnd: { isEditingName = false }
            )
            .fixedSize()
        } else {
            Text(name)
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .foregroundStyle(Color.white.opacity(0.9))
                .lineLimit(1)
                .contentShape(Rectangle())
                .onTapGesture { Workspace.shared.focusedID = id; isEditingName = true }
                .onHover { hovering in
                    if hovering { NSCursor.pointingHand.set() } else { NSCursor.arrow.set() }
                }
        }
    }

    /// Editable gray description (max 40 chars), right-aligned. Truncates with an
    /// ellipsis when the header gets tight on a narrow window.
    @ViewBuilder
    private var detailField: some View {
        if isEditingDetail {
            InlineField(
                text: $detail,
                font: .monospacedSystemFont(ofSize: 12, weight: .regular),
                color: NSColor.white.withAlphaComponent(0.55),
                alignment: .right,
                placeholder: "Add a description",
                maxLength: maxDetail,
                onEnd: { isEditingDetail = false }
            )
            .frame(maxWidth: 280)
        } else if !detail.isEmpty {
            detailLabel(detail, opacity: 0.45)
        } else if isHoveringHeader {
            // Empty + hovering the header → reveal the placeholder.
            detailLabel("Add a description", opacity: 0.22)
        }
        // Empty + not hovering → show nothing.
    }

    private func detailLabel(_ text: String, opacity: Double) -> some View {
        Text(text)
            .font(.system(size: 12, design: .monospaced))
            .foregroundStyle(Color.white.opacity(opacity))
            .lineLimit(1)
            .truncationMode(.tail)
            .contentShape(Rectangle())
            .onTapGesture { Workspace.shared.focusedID = id; isEditingDetail = true }
            .onHover { hovering in
                if hovering { NSCursor.pointingHand.set() } else { NSCursor.arrow.set() }
            }
    }

    /// Drag handle on the bottom edge only; the top edge is inert.
    private var bottomEdgeHandle: some View {
        Color.clear
            .frame(height: edgeGrab)
            .contentShape(Rectangle())
            .onHover { hovering in
                if hovering { NSCursor.resizeUpDown.set() } else { NSCursor.arrow.set() }
            }
            // High priority so resizing wins over the ScrollView's own drag.
            // Measure in .global space so the moving edge doesn't feed back into
            // the gesture and cause jitter.
            .highPriorityGesture(
                DragGesture(coordinateSpace: .global)
                    .onChanged { value in
                        if startHeight == nil { startHeight = height }
                        let base = startHeight ?? height
                        height = min(max(minHeight, base + value.translation.height), maxHeight)
                    }
                    .onEnded { _ in startHeight = nil }
            )
    }
}

/// Forces the host NSWindow to drop its titlebar entirely: full-size content
/// view, transparent/hidden titlebar, and draggable by the window background
/// (since there's no titlebar to grab).
private struct WindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { WindowConfigView() }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

private final class WindowConfigView: NSView {
    private let buttonTypes: [NSWindow.ButtonType] = [.closeButton, .miniaturizeButton, .zoomButton]
    private var defaultOrigins: [NSWindow.ButtonType: NSPoint] = [:]

    // How far to inset the traffic lights from their default corner position.
    private let insetX: CGFloat = 12
    private let insetY: CGFloat = 8   // moved down (more top padding)

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window else { return }
        window.styleMask.insert(.fullSizeContentView)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden

        // Capture the system's default button positions once, so re-pinning is
        // absolute (default + inset) and never accumulates.
        if defaultOrigins.isEmpty {
            for type in buttonTypes {
                if let button = window.standardWindowButton(type) {
                    defaultOrigins[type] = button.frame.origin
                }
            }
        }
        repositionTrafficLights()

        // AppKit re-lays the buttons out on these events; re-pin each time.
        let nc = NotificationCenter.default
        for name: NSNotification.Name in [
            .init("NSWindowDidBecomeKeyNotification"),
            .init("NSWindowDidResizeNotification"),
            .init("NSWindowDidEndLiveResizeNotification"),
        ] {
            nc.addObserver(self, selector: #selector(repositionTrafficLights),
                           name: name, object: window)
        }
    }

    @objc private func repositionTrafficLights() {
        guard let window else { return }
        for type in buttonTypes {
            guard let button = window.standardWindowButton(type),
                  let origin = defaultOrigins[type] else { continue }
            // Clamp Y so we never push a button off the bottom of its container.
            let y = max(3, origin.y - insetY)
            button.setFrameOrigin(NSPoint(x: origin.x + insetX, y: y))
        }
    }

    deinit { NotificationCenter.default.removeObserver(self) }
}

/// Activate as a normal foreground app (dock icon + focus), even when launched
/// via `swift run` outside an .app bundle.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var scrollMonitor: Any?

    private var clickMonitor: Any?
    private var keyMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        AgentControl.install()
        installCmdScrollMonitor()
        installClickFocusMonitor()
        installShortcutMonitor()
        Workspace.shared.startAgentWatch()
        GitHubFeed.shared.startPolling()
        observeFullScreen()
    }

    private func observeFullScreen() {
        let nc = NotificationCenter.default
        nc.addObserver(forName: NSWindow.didEnterFullScreenNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { Workspace.shared.isFullScreen = true }
        }
        nc.addObserver(forName: NSWindow.didExitFullScreenNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { Workspace.shared.isFullScreen = false }
        }
    }

    /// App-level keyboard shortcuts for the agent list. A local monitor catches
    /// these even while a terminal is first responder (⌘-combos don't reach the
    /// shell anyway), and swallows the ones it handles.
    private func installShortcutMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            nonisolated(unsafe) let ev = event
            let handled: Bool = MainActor.assumeIsolated { AppDelegate.handleShortcut(ev) }
            return handled ? nil : event
        }
    }

    @MainActor
    private static func handleShortcut(_ ev: NSEvent) -> Bool {
        let mods = ev.modifierFlags.intersection([.command, .option, .shift, .control])
        let ws = Workspace.shared
        let key = ev.charactersIgnoringModifiers?.lowercased() ?? ""
        let code = ev.keyCode          // 126 = up, 125 = down, 36 = return

        if mods == [.command] {
            if key == "n" { ws.newBox(); return true }
            if key == "w" { return ws.closeFocused() }          // else fall through → window close
            if let d = Int(key), (1...9).contains(d) { ws.focus(index: d - 1); return true }
        } else if mods == [.command, .option] {
            // Match letters by physical keyCode — with Option held,
            // charactersIgnoringModifiers can return composed chars (⌥Q → "œ"),
            // which would let ⌘⌥Q fall through to Quit.
            if code == 126 { ws.focus(offset: -1); return true }  // ⌘⌥↑
            if code == 125 { ws.focus(offset: 1); return true }   // ⌘⌥↓
            if code == 36 { ws.toggleSolo(); return true }        // ⌘⌥⏎ solo/zoom
            if code == 0 { ws.toggleAccordion(); return true }    // ⌘⌥A
            if code == 12 { ws.toggleQuick(); return true }       // ⌘⌥Q quick terminal
        } else if mods == [.command, .option, .shift] {
            if code == 126 { ws.moveFocused(by: -1); return true } // ⌘⌥⇧↑ reorder
            if code == 125 { ws.moveFocused(by: 1); return true }  // ⌘⌥⇧↓ reorder
        }
        return false
    }

    /// Clicking inside a terminal focuses its box (resolved via the registry).
    /// Doesn't swallow the click — the terminal still gets it.
    private func installClickFocusMonitor() {
        clickMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { event in
            nonisolated(unsafe) let ev = event
            let swallow: Bool = MainActor.assumeIsolated {
                guard let window = ev.window,
                      let hit = window.contentView?.hitTest(ev.locationInWindow),
                      let id = TerminalRegistry.shared.boxID(under: hit) else { return false }
                let changingFocus = id != Workspace.shared.focusedID
                Workspace.shared.focusedID = id
                // In accordion mode a focus change resizes the boxes; swallow that
                // first click so the terminal doesn't begin a stray selection while
                // it reflows. A second click then interacts with the terminal.
                return changingFocus && Workspace.shared.accordion
            }
            return swallow ? nil : event
        }
    }

    /// ⌘ + scroll-wheel scrolls the enclosing list (the right pane) instead of the
    /// terminal under the cursor. Plain scroll still goes to the terminal scrollback.
    /// Implemented as a local event monitor so GhosttyKit's view is untouched.
    private func installCmdScrollMonitor() {
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
            // Local event monitors fire on the main thread, so the event is safe.
            nonisolated(unsafe) let ev = event
            // Returns true if we handled the event ourselves (swallow it).
            let swallow: Bool = MainActor.assumeIsolated {
                guard let window = ev.window,
                      let hit = window.contentView?.hitTest(ev.locationInWindow)
                else { return false }

                // Left pane (the activity feed) scrolls natively — the ⌘-lock is
                // only for the right/terminal pane.
                if ev.locationInWindow.x < Workspace.shared.leftWidth { return false }

                // Walk up: find the terminal (if any) and the enclosing list scroll view.
                var node: NSView? = hit
                var terminal: NSView?
                var list: NSScrollView?
                while let cur = node {
                    if terminal == nil, cur is GhosttyTerminalView { terminal = cur }
                    if let sv = cur as? NSScrollView { list = sv; break }
                    node = cur.superview
                }

                if ev.modifierFlags.contains(.command) {
                    list?.scrollWheel(with: ev)        // ⌘-scroll → scroll the list
                    return true
                }
                if terminal != nil {
                    // Let AppKit dispatch natively — manually delivering + swallowing
                    // broke momentum/precise-scroll continuity (huge jumps). The
                    // terminal view consumes scroll without bubbling, so it won't
                    // reach the list.
                    return false
                }
                // Plain scroll over gaps / header / background inside the list:
                // do nothing. The list only scrolls with ⌘ held.
                return list != nil
            }
            return swallow ? nil : event
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationWillTerminate(_ notification: Notification) {
        Workspace.shared.saveIfNeeded()
    }
}
