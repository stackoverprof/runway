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
                .frame(minWidth: 780, minHeight: 480)
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
        DispatchQueue.main.async { Self.configureCloseWindowMenuItem() }
        AgentControl.install()
        AgentControl.resetStates()   // clear stale agent dots from the last session
        installTerminalScrollMonitor()
        installClickFocusMonitor()
        installShortcutMonitor()
        observeFullScreen()
    }

    /// SwiftUI supplies its own File > Close command for every WindowGroup.
    /// Keep that visible menu item aligned with Runway's close-window binding.
    @MainActor
    private static func configureCloseWindowMenuItem() {
        guard let fileMenu = NSApp.mainMenu?.items
            .compactMap(\.submenu)
            .first(where: { $0.title == "File" }),
              let closeItem = fileMenu.items.first(where: {
                  $0.action == #selector(NSWindow.performClose(_:)) || $0.title == "Close"
              }) else { return }

        closeItem.title = "Close Window"
        closeItem.keyEquivalent = "w"
        closeItem.keyEquivalentModifierMask = [.command, .shift]
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

        // Window closing does not require a workspace. Handle it first so it
        // also works in Settings and any other auxiliary window.
        if KeyBindings.shared.chord(for: .closeWindow).matches(ev) {
            guard let window = ev.window ?? NSApp.keyWindow else { return false }
            window.performClose(nil)
            return true
        }

        guard let context = RunwayWindowRegistry.shared.context(for: ev.window) ?? RunwayWindowRegistry.shared.activeContext() else {
            return false
        }
        let ws = context.workspace
        let mods = ev.modifierFlags.intersection([.command, .option, .shift, .control])

        // Fixed: ⌘F toggles search for whichever left-pane tab is active.
        if mods == [.command], ev.keyCode == 3 {
            ws.requestFind()
            return true
        }

        // Fixed: ⌘1–9 jump to a card.
        if mods == [.command], let key = ev.charactersIgnoringModifiers,
           let d = Int(key), (1...9).contains(d) {
            ws.focus(index: d - 1); return true
        }

        // Option-Command-1/2/3 jumps to Runway/Feeds/PR tab.
        if mods == [.command, .option], let key = ev.charactersIgnoringModifiers,
           let d = Int(key), (1...3).contains(d) {
            let tabs = FeedTab.allCases
            ws.selectedTab = tabs[d - 1]
            return true
        }

        // Shift-Command-[ and Shift-Command-] also cycle tabs (browser habit).
        if mods == [.command, .shift], let key = ev.charactersIgnoringModifiers {
            if key == "[" { ws.cycleTab(by: -1); return true }
            if key == "]" { ws.cycleTab(by: 1); return true }
        }

        // ⌘⌥[ / ⌘⌥] step through Runway, Feeds, Pulls; ⌘⌥, / ⌘⌥. step through
        // the subtabs of whichever tab is showing (Open/Closed, the feed filter,
        // the Pulls timeframe), and ⌘⌥⇧1–5 jump straight to one. Without these
        // the keyboard stopped at the three top-level tabs and every subtab
        // needed the mouse.
        if mods == [.command, .option] {
            if ev.keyCode == 33 { ws.cycleTab(by: -1); return true }      // ⌘⌥[
            if ev.keyCode == 30 { ws.cycleTab(by: 1); return true }       // ⌘⌥]
            if ev.keyCode == 43 { ws.cycleSubtab(by: -1); return true }   // ⌘⌥,
            if ev.keyCode == 47 { ws.cycleSubtab(by: 1); return true }    // ⌘⌥.
        }
        if mods == [.command, .option, .shift], let digit = Self.digit(for: ev.keyCode),
           digit <= ws.subtabLabels.count {
            ws.selectSubtab(index: digit - 1)
            return true
        }

        // Arrow navigation follows the layout: the agents run down the pane in
        // the vertical stack and across it in the horizontal one, while the
        // quick terminal is always ← away, as the cell left of the first agent.
        // Bound chords
        // still win, except for the four navigation actions, which mean the same
        // thing here as they do below.
        let bound = KeyBindings.shared.action(for: ev)
        if bound == nil || Self.arrowNavigable.contains(bound!),
           mods == [.command, .option] || mods == [.command, .option, .shift],
           let outcome = ArrowNavigation.outcome(
               keyCode: ev.keyCode,
               shifted: mods.contains(.shift),
               axis: ws.terminalLayoutAxis,
               quickTerminalVisible: ws.quickVisible,
               quickTerminalFocused: ws.quickHasKeyboard?() ?? false,
               focusedIsFirstAgent: ws.activeBoxes.first?.id == ws.focusedID
           ) {
            switch outcome {
            case .focusPrevious:      ws.focus(offset: -1)
            case .focusNext:          ws.focus(offset: 1)
            case .reorderPrevious:    ws.moveFocused(by: -1)
            case .reorderNext:        ws.moveFocused(by: 1)
            case .focusQuickTerminal: ws.focusQuick?()
            case .focusAgents:        TerminalRegistry.shared.focusTerminal(ws.focusedID)
            }
            return true
        }

        switch bound {
        case .newBox:        ws.newBox()
        case .closeBox:      return ws.closeFocused()   // else fall through → window close
        case .closeWindow:   return false               // handled before workspace lookup
        case .navigatePrev:  ws.focus(offset: -1)
        case .navigateNext:  ws.focus(offset: 1)
        case .reorderUp:     ws.moveFocused(by: -1)
        case .reorderDown:   ws.moveFocused(by: 1)
        case .solo:          ws.toggleSolo()
        case .quickTerminal: ws.toggleQuick()
        case .repoPicker:    ws.requestRepoPicker()
        case .layoutAxis:    ws.toggleLayoutAxis()
        case .none:          return false
        }
        return true
    }

    /// Actions whose arrow chords the layout may reinterpret, because the arrow
    /// handler above resolves them to the same move.
    private static let arrowNavigable: Set<AppAction> = [
        .navigatePrev, .navigateNext, .reorderUp, .reorderDown,
    ]

    /// Number-row key codes, matched by position so a modifier that composes a
    /// different character (⇧1 → "!") still reads as the digit.
    private static func digit(for keyCode: UInt16) -> Int? {
        switch keyCode {
        case 18: 1
        case 19: 2
        case 20: 3
        case 21: 4
        case 23: 5
        case 22: 6
        case 26: 7
        case 28: 8
        case 25: 9
        default: nil
        }
    }

    /// Clicking inside a terminal focuses its box (resolved via the registry).
    /// Doesn't swallow the click — the terminal still gets it.
    private func installClickFocusMonitor() {
        clickMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { event in
            nonisolated(unsafe) let ev = event
            let swallow: Bool = MainActor.assumeIsolated {
                guard let window = ev.window else { return false }
                guard
                      let hit = window.contentView?.hitTest(ev.locationInWindow),
                      let id = TerminalRegistry.shared.boxID(under: hit) else { return false }
                guard let ws = RunwayWindowRegistry.shared.context(for: window)?.workspace else { return false }
                let changingFocus = id != ws.focusedID
                // setFocus (not just focusedID) so the clicked terminal also becomes
                // the keyboard first responder — otherwise the glow moves but typing
                // stays on the previously-focused terminal.
                ws.setFocus(id)
                // A focus change resizes the accordion. Swallow that first click so
                // the terminal does not begin a stray selection while it reflows.
                return changingFocus
            }
            return swallow ? nil : event
        }
    }

    /// Tame dense trackpad scrolling over terminals so mouse-reporting TUIs do
    /// not overshoot. The right pane itself no longer scrolls.
    private func installTerminalScrollMonitor() {
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
            // Local event monitors fire on the main thread, so the event is safe.
            nonisolated(unsafe) let ev = event
            // Returns true if we handled the event ourselves (swallow it).
            let swallow: Bool = MainActor.assumeIsolated {
                guard let window = ev.window,
                      let hit = window.contentView?.hitTest(ev.locationInWindow)
                else { return false }

                // Walk up to determine whether the pointer is over a terminal.
                var node: NSView? = hit
                var terminal: NSView?
                while let cur = node {
                    if terminal == nil, cur is GhosttyTerminalView { terminal = cur }
                    node = cur.superview
                }

                // Over a terminal (agent grid OR the quick-terminal overlay): tame
                // trackpad scroll so TUIs don't overshoot.
                if terminal != nil {
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

                return false
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
