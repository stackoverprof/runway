import SwiftUI
import AppKit

@main
struct RunwayApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        SettingsKey.registerDefaults()
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
        let mods = ev.modifierFlags.intersection([.command, .option, .shift, .control])

        // Fixed: ⌘F toggles search for whichever tab is active.
        if mods == [.command], ev.keyCode == 3 {
            ws.requestFind()
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
        case .closeWindow:   return false               // handled before the lookup
        case .repoPicker:    ws.requestRepoPicker()
        case .none:          return false
        }
        return true
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
