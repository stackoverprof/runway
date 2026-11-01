import SwiftUI
import AppKit
import GhosttyKit

@main
struct RunwayApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        // A relaunch from inside an agent would otherwise hand every terminal
        // that agent's Claude session variables.
        for name in ProcessInfo.processInfo.environment.keys where name.hasPrefix("CLAUDE") {
            unsetenv(name)
        }
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

        Settings { SettingsView() }
    }
}

/// Activate as a normal foreground app (dock icon + focus), even when launched
/// via `swift run` outside an .app bundle.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var keyMonitor: Any?
    private var scrollMonitor: Any?

    /// Runway's palette is hand-picked near-black; every surface color is a
    /// literal, not a semantic one. Left on the system appearance, flipping the
    /// Mac to Light turned the few semantic bits into dark-on-dark mush, so pin
    /// the whole app to Dark once, before any window exists.
    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.appearance = NSAppearance(named: .darkAqua)
        // `runway://` links arrive as a GetURL Apple event. Handling it here,
        // rather than through SwiftUI's scene routing, keeps a link from opening
        // a second window or activating the app.
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleGetURL(_:withReply:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )
    }

    @objc private func handleGetURL(_ event: NSAppleEventDescriptor, withReply reply: NSAppleEventDescriptor) {
        guard let link = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue,
              let url = URL(string: link) else { return }
        MainActor.assumeIsolated { RunwayURLCommand.handle(url) }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.async { Self.configureCloseWindowMenuItem() }
        AgentControl.install()
        Walkthrough.install()
        AgentControl.resetStates()
        installShortcutMonitor()
        installTerminalScrollMonitor()
        observeFullScreen()
    }

    /// Tame dense trackpad scrolling over terminals so mouse-reporting TUIs
    /// like Claude do not overshoot. Every terminal in Runway gets this, the
    /// pilot's and a crew's and the ATC panel's, so they all scroll alike.
    private func installTerminalScrollMonitor() {
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
            // Local event monitors fire on the main thread, so the event is safe.
            nonisolated(unsafe) let ev = event
            // True when we handled the event ourselves, and swallow it.
            let swallow: Bool = MainActor.assumeIsolated {
                guard let window = ev.window,
                      let hit = window.contentView?.hitTest(ev.locationInWindow)
                else { return false }

                var node: NSView? = hit
                var terminal: NSView?
                while let current = node {
                    if terminal == nil, current is GhosttyTerminalView { terminal = current }
                    node = current.superview
                }
                guard terminal != nil else { return false }

                // Drop momentum, which overshoots a mouse-reporting TUI, then
                // throttle the dense precise-scroll stream. A coarse mouse
                // wheel is not precise and passes through untouched.
                if !ev.momentumPhase.isEmpty { return true }
                if ev.hasPreciseScrollingDeltas {
                    guard let ws = RunwayWindowRegistry.shared
                        .context(for: ev.window)?.workspace else { return false }
                    let since = ev.timestamp - ws.lastTerminalScrollTS
                    if since < 0.055 { return true }
                    ws.lastTerminalScrollTS = ev.timestamp
                }
                return false
            }
            return swallow ? nil : event
        }
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

    /// App-level keyboard shortcuts. A local monitor catches these first and
    /// swallows the ones it handles.
    private func installShortcutMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
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
        let issues = context.issues

        // While the palette is up it owns the keyboard, bar the chord that
        // closes it again and the one that opened it.
        if ws.paletteVisible {
            if KeyBindings.shared.chord(for: .palette).matches(ev) {
                ws.paletteVisible = false
                return true
            }
            return false
        }
        let mods = ev.modifierFlags.intersection([.command, .option, .shift, .control])
        let quickFocused = ws.isQuickTerminalFocused

        // ⌘T, ⌘W, ⌘1-9 and ⌘⇧[ ] drive the ATC panel's tabs while it has the
        // keyboard, the way a browser's do.
        if quickFocused, mods == [.command] {
            if ev.keyCode == 17 { ws.requestQuickTabAction(.new); return true }
            if ev.keyCode == 13 { ws.requestQuickTabAction(.close); return true }
            if let key = ev.charactersIgnoringModifiers, let index = Int(key), (1...9).contains(index) {
                ws.requestQuickTabAction(.select(index))
                return true
            }
        }
        if quickFocused, mods == [.command, .shift] {
            if ev.keyCode == 33 { ws.requestQuickTabAction(.cycle(-1)); return true }
            if ev.keyCode == 30 { ws.requestQuickTabAction(.cycle(1)); return true }
        }

        // Fixed: ⌘F toggles search for whichever tab is active.
        if mods == [.command], ev.keyCode == 3 {
            ws.requestFind()
            return true
        }

        // ⌘1-9 is the nth flight in the lane on screen, and ⌘⌃1-9 the nth
        // crew of the flight. The panes left to right, the modifiers one by
        // one: the keyboard says which pane you mean.
        if mods == [.command], let digit = Self.digit(for: ev.keyCode) {
            FlightRoster.select(number: digit, in: issues, ws: ws)
            return true
        }
        if mods == [.command, .control], let digit = Self.digit(for: ev.keyCode) {
            FlightCrews.select(number: digit, in: issues, ws: ws)
            return true
        }

        // ⌘⌥1/2 jumps to Feeds or Pulls. Repeating the shortcut for the tab
        // already in front performs the same refresh-and-top reset as clicking
        // that tab again.
        if mods == [.command, .option], let key = ev.charactersIgnoringModifiers,
           let digit = Int(key), (1...FeedTab.allCases.count).contains(digit) {
            let tab = FeedTab.allCases[digit - 1]
            if ws.selectedTab == tab {
                ws.requestTabReset()
            } else {
                ws.selectedTab = tab
            }
            return true
        }

        // Shift-Command-[ and Shift-Command-] also cycle tabs (browser habit).
        if mods == [.command, .shift], let key = ev.charactersIgnoringModifiers {
            if key == "[" { ws.cycleTab(by: -1); return true }
            if key == "]" { ws.cycleTab(by: 1); return true }
        }

        // ⌘⌥[ / ⌘⌥] step through the tabs; ⌘⌥, / ⌘⌥. step through whichever
        // options the tab in front offers, and ⌘⌥⇧1–5 jump straight to one.
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

        switch KeyBindings.shared.action(for: ev) {
        case .closeWindow:     return false             // handled before the lookup
        case .repoPicker:      ws.requestRepoPicker()
        case .quickTerminal:   ws.toggleQuick()
        case .palette:         openPalette(ws, in: ev.window)
        case .nextFlight:      FlightRoster.step(by: 1, in: issues, ws: ws)
        case .previousFlight:  FlightRoster.step(by: -1, in: issues, ws: ws)
        case .nextCrew:        FlightCrews.step(by: 1, in: issues, ws: ws)
        case .previousCrew:    FlightCrews.step(by: -1, in: issues, ws: ws)
        case .toggleCrew:      FlightCrews.toggle(in: issues, ws: ws)
        case .nextSection:     ws.cycleSection(by: 1)
        case .previousSection: ws.cycleSection(by: -1)
        case .leaveTerminal:   leaveTerminal(ws, in: ev.window)
        case .none:            return false
        }
        return true
    }

    /// Hand the keyboard back to the panes.
    ///
    /// A terminal keeps every key it is given, so without this the only way
    /// out of one is the mouse. Resigning first responder is enough: the
    /// panes take their own keys from the monitor, not from focus.
    @MainActor
    private static func leaveTerminal(_ ws: Workspace, in window: NSWindow?) {
        let window = window ?? NSApp.keyWindow
        window?.makeFirstResponder(window?.contentView)
        ws.setFocus(nil)
    }

    /// The palette has to hold the keyboard itself, so the terminal under it
    /// lets go before it opens.
    @MainActor
    private static func openPalette(_ ws: Workspace, in window: NSWindow?) {
        leaveTerminal(ws, in: window)
        ws.paletteVisible = true
    }

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

    /// Let Ghostty receive the down, drag, and up for text selection. A simple
    /// click focuses on release; a drag only selects and restores the previous
    /// keyboard responder after Ghostty finishes its copy-on-select handling.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Each window saves itself on its own polling loop; nothing global to do.
    }
}
