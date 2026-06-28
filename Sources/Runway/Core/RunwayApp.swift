import SwiftUI
import AppKit
import GhosttyKit

@main
struct RunwayApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.openWindow) private var openWindow

    init() {
        SettingsKey.registerDefaults()
        // Must run before any terminal (GhosttyKit) loads its config.
        RunwayTerminal.installTheme()
    }

    var body: some Scene {
        WindowGroup("Runway", id: "main") {
            ContentView()
                .frame(minWidth: 720, minHeight: 480)
                .ignoresSafeArea()
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 1100, height: 720)
        .commandsRemoved()
        .commands {
            CommandGroup(after: .newItem) {
                Button("New Window") {
                    openWindow(id: "main")
                }
                .keyboardShortcut("n", modifiers: [.command, .shift])
            }
        }

        Settings { SettingsView() }
    }
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
        AgentControl.resetStates()   // clear stale agent dots from the last session
        installCmdScrollMonitor()
        installClickFocusMonitor()
        installShortcutMonitor()
        observeFullScreen()
    }

    private func observeFullScreen() {
        let nc = NotificationCenter.default
        nc.addObserver(forName: NSWindow.didEnterFullScreenNotification, object: nil, queue: .main) { note in
            let window = note.object as? NSWindow
            MainActor.assumeIsolated {
                RunwayWindowRegistry.shared.context(for: window)?.workspace.isFullScreen = true
            }
        }
        nc.addObserver(forName: NSWindow.didExitFullScreenNotification, object: nil, queue: .main) { note in
            let window = note.object as? NSWindow
            MainActor.assumeIsolated {
                RunwayWindowRegistry.shared.context(for: window)?.workspace.isFullScreen = false
            }
        }
    }

    /// Confirm before quitting (⌘Q / menu / Dock) so a stray keystroke doesn't
    /// kill all the running agent sessions.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard UserDefaults.standard.bool(forKey: SettingsKey.confirmQuit) else { return .terminateNow }
        let alert = NSAlert()
        alert.messageText = "Quit Runway?"
        alert.informativeText = "Your running agent sessions will be stopped."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Quit")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn ? .terminateNow : .terminateCancel
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
        if KeyBindings.shared.recording { return false }   // Settings is capturing a chord
        guard let context = RunwayWindowRegistry.shared.context(for: ev.window) ?? RunwayWindowRegistry.shared.activeContext() else {
            return false
        }
        let ws = context.workspace
        let mods = ev.modifierFlags.intersection([.command, .option, .shift, .control])

        // Fixed: ⌘1–9 jump to a card.
        if mods == [.command], let key = ev.charactersIgnoringModifiers,
           let d = Int(key), (1...9).contains(d) {
            ws.focus(index: d - 1); return true
        }

        // While the quick terminal is open: ⌘⌥← / ⌘⌥→ jump between it (left) and
        // the focused agent (right).
        if ws.quickVisible, mods == [.command, .option] {
            if ev.keyCode == 123 { ws.focusQuick?(); return true }                          // ⌘⌥←
            if ev.keyCode == 124 { TerminalRegistry.shared.focusTerminal(ws.focusedID); return true }  // ⌘⌥→
        }

        switch KeyBindings.shared.action(for: ev) {
        case .newBox:        ws.newBox()
        case .closeBox:      return ws.closeFocused()   // else fall through → window close
        case .navigatePrev:  ws.focus(offset: -1)
        case .navigateNext:  ws.focus(offset: 1)
        case .reorderUp:     ws.moveFocused(by: -1)
        case .reorderDown:   ws.moveFocused(by: 1)
        case .accordion:     ws.toggleAccordion()
        case .solo:          ws.toggleSolo()
        case .quickTerminal: ws.toggleQuick()
        case .none:          return false
        }
        return true
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
                guard let ws = RunwayWindowRegistry.shared.context(for: window)?.workspace else { return false }
                let changingFocus = id != ws.focusedID
                // setFocus (not just focusedID) so the clicked terminal also becomes
                // the keyboard first responder — otherwise the glow moves but typing
                // stays on the previously-focused terminal.
                ws.setFocus(id)
                // In accordion mode a focus change resizes the boxes; swallow that
                // first click so the terminal doesn't begin a stray selection while
                // it reflows. A second click then interacts with the terminal.
                return changingFocus && ws.accordion
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

                // Walk up: find the terminal (if any) and the enclosing list scroll view.
                var node: NSView? = hit
                var terminal: NSView?
                var list: NSScrollView?
                while let cur = node {
                    if terminal == nil, cur is GhosttyTerminalView { terminal = cur }
                    if let sv = cur as? NSScrollView { list = sv; break }
                    node = cur.superview
                }

                // Over a terminal (agent grid OR the quick-terminal overlay): tame
                // trackpad scroll so TUIs don't overshoot.
                if terminal != nil {
                    if ev.modifierFlags.contains(.command) {
                        list?.scrollWheel(with: ev)    // ⌘-scroll → scroll the enclosing list
                        return true
                    }
                    // Drop momentum (inertia overshoots mouse-reporting TUIs like
                    // claude), then throttle the dense precise-scroll stream;
                    // coarse mouse wheels (not precise) pass untouched.
                    if !ev.momentumPhase.isEmpty { return true }
                    if ev.hasPreciseScrollingDeltas {
                        guard let ws = RunwayWindowRegistry.shared.context(for: ev.window)?.workspace else { return false }
                        let dt = ev.timestamp - ws.lastTerminalScrollTS
                        if dt < 0.055 { return true }
                        ws.lastTerminalScrollTS = ev.timestamp
                    }
                    return false
                }

                // Not over a terminal: the left pane (activity feed) scrolls
                // natively; the right pane only scrolls its list with ⌘ held.
                guard let ws = RunwayWindowRegistry.shared.context(for: ev.window)?.workspace else { return false }
                if ev.locationInWindow.x < ws.leftWidth { return false }
                if ev.modifierFlags.contains(.command) { list?.scrollWheel(with: ev); return true }
                return list != nil
            }
            return swallow ? nil : event
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Each window saves itself on its own polling loop; nothing global to do.
    }
}
