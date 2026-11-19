import AppKit
import Carbon.HIToolbox
import SwiftUI

@main
struct RunwayWidgetApp: App {
    @NSApplicationDelegateAdaptor(WidgetAppDelegate.self) private var delegate

    init() {
        SettingsKey.registerDefaults()
        RunwayFont.register()
        UserDefaults.standard.register(defaults: ["runway.repo": "VISKA-IO/monorepo"])
    }

    var body: some Scene {
        Settings { EmptyView() }
    }
}

/// A borderless panel that can take keyboard focus (for the repo picker
/// and menus) and hides itself when you click anywhere else.
final class WidgetPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// Owns the menu bar item and the panel. The panel docks to the left edge
/// of the screen, full height, with a gap all around. It opens from the
/// menu bar icon, Cmd+Option+Q, or a two-finger swipe right with the pointer
/// at the screen's left edge, and follows your fingers like Notification
/// Center; a two-finger swipe left over it puts it away.
@MainActor
final class WidgetAppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    static let gap: CGFloat = 10
    static let width: CGFloat = 420

    private var statusItem: NSStatusItem!
    private var panel: WidgetPanel!

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = MenuBarIcon.image
        statusItem.button?.target = self
        statusItem.button?.action = #selector(toggle)

        panel = WidgetPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false  // the window shadow is square; the glass draws its own edge
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.delegate = self
        panel.acceptsMouseMovedEvents = true

        let root = SlidingPanel(state: slide, travel: Self.width + Self.gap * 2) {
            BlackPanel { WidgetView() }
                .padding(.leading, Self.gap)
        }
        .preferredColorScheme(.dark)
        let host = NSHostingView(rootView: root)
        host.wantsLayer = true
        host.layer?.backgroundColor = .clear
        panel.contentView = host

        registerHotKey()
        watchEdgeSwipes()

        NotificationCenter.default.addObserver(
            self, selector: #selector(place),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)
    }

    /// The screen under the pointer: where you swiped or clicked.
    private var screen: NSScreen? {
        let point = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(point, $0.frame, false) } ?? NSScreen.main
    }

    private let slide = SlideState()

    /// The window runs from the very left edge of the screen to the panel's
    /// right side, so the content slides in from the edge and is clipped by
    /// the window instead of spilling onto a monitor to the left.
    private var restingFrame: NSRect? {
        guard let frame = screen?.visibleFrame else { return nil }
        let g = Self.gap
        return NSRect(x: frame.minX, y: frame.minY + g,
                      width: Self.width + g, height: frame.height - g * 2)
    }

    @objc private func place() {
        guard !panel.isVisible, let rest = restingFrame else { return }
        panel.setFrame(rest, display: true)
    }

    private var hiding = false
    private var isOpen: Bool { panel.isVisible && !hiding }

    private func show() {
        if !isOpen { NotificationCenter.default.post(name: .widgetShown, object: nil) }
        hiding = false
        if !panel.isVisible, let rest = restingFrame { panel.setFrame(rest, display: true) }
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        withAnimation(.timingCurve(0.2, 0.9, 0.25, 1, duration: 0.32)) { slide.progress = 1 }
    }

    func close() { hide() }

    private func hide() {
        guard panel.isVisible, !hiding else { return }
        hiding = true
        withAnimation(.timingCurve(0.5, 0, 0.75, 0.2, duration: 0.24)) {
            slide.progress = 0
        } completion: { [weak self] in
            guard let self, self.hiding else { return }
            self.panel.orderOut(nil)
            self.hiding = false
        }
    }

    // MARK: Edge swipe

    private var gesture: (opening: Bool, travelled: CGFloat)?
    private var swipeMonitors: [Any] = []

    /// Two-finger horizontal scrolls. Global ones (over other apps) can open
    /// it from the left edge; local ones (over the panel) can close it.
    /// Mouse events need no Accessibility permission.
    private func watchEdgeSwipes() {
        if let global = NSEvent.addGlobalMonitorForEvents(matching: .scrollWheel, handler: { [weak self] event in
            MainActor.assumeIsolated { _ = self?.handleSwipe(event) }
        }) { swipeMonitors.append(global) }
        if let local = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel, handler: { [weak self] event in
            let used: Bool = MainActor.assumeIsolated { self?.handleSwipe(event) ?? false }
            return used ? nil : event
        }) { swipeMonitors.append(local) }
    }

    /// Returns true when the event drove the panel (so a local scroll view
    /// doesn't also scroll).
    @discardableResult
    private func handleSwipe(_ event: NSEvent) -> Bool {
        // Fling momentum after lifting the fingers is not a gesture.
        guard event.momentumPhase.isEmpty, event.hasPreciseScrollingDeltas else { return false }
        // Finger movement, whatever the natural scrolling setting.
        let dx = event.isDirectionInvertedFromDevice ? event.scrollingDeltaX : -event.scrollingDeltaX
        let travel = Self.width + Self.gap
        if event.phase == .began {
            gesture = nil
            guard abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) || event.scrollingDeltaY == 0 else { return false }
            if !isOpen, atLeftEdge {
                gesture = (opening: true, travelled: 0)
                hiding = false
                if !panel.isVisible, let rest = restingFrame {
                    panel.setFrame(rest, display: true)
                    slide.progress = 0
                    panel.orderFrontRegardless()
                }
            } else if isOpen, NSMouseInRect(NSEvent.mouseLocation, panel.frame, false) {
                gesture = (opening: false, travelled: 0)
            }
            return false
        }
        guard var current = gesture else { return false }
        if event.phase == .changed {
            current.travelled += dx
            gesture = current
            let progress = current.opening ? current.travelled / travel : 1 + current.travelled / travel
            // A vertical scroll that started sideways stays a scroll.
            if !current.opening, abs(current.travelled) < 12 { return false }
            slide.progress = min(max(progress, 0), 1)
            return true
        }
        if event.phase == .ended || event.phase == .cancelled {
            gesture = nil
            let keep = current.opening ? slide.progress > 0.3 : slide.progress > 0.7
            if keep { show() } else { hide() }
            return true
        }
        return false
    }

    /// The pointer pressed against the left edge of its screen.
    private var atLeftEdge: Bool {
        guard let screen else { return false }
        return NSEvent.mouseLocation.x - screen.frame.minX <= 4
    }

    private var hotKeyQ: EventHotKeyRef?
    static weak var shared: WidgetAppDelegate?

    /// Cmd+Option+Q toggles the panel from anywhere. Carbon hot keys need
    /// no Accessibility permission.
    private func registerHotKey() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        Self.shared = self
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            MainActor.assumeIsolated { WidgetAppDelegate.shared?.toggle() }
            return noErr
        }, 1, &spec, nil, nil)
        // Cmd+Option+Q, the chord Runway used.
        let idQ = EventHotKeyID(signature: OSType(0x5257_4447), id: 2)
        RegisterEventHotKey(UInt32(kVK_ANSI_Q), UInt32(cmdKey | optionKey), idQ,
                            GetApplicationEventTarget(), 0, &hotKeyQ)
    }

    @objc func toggle() {
        if panel.isVisible && !hiding { hide() } else { show() }
    }

    /// Set by the menu's own Quit item, which is deliberate and needs no question.
    static var quitChosen = false

    /// Confirm before quitting from Cmd+Q (or the Dock / Activity Monitor's
    /// polite quit), since the chord sits right next to Cmd+Option+Q and a
    /// stray press would close the widget. The ellipsis menu's Quit skips it.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if Self.quitChosen { return .terminateNow }
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Quit Runway Widget?"
        alert.informativeText = "It leaves the menu bar until you open it again."
        // Cancel is the default (Return), so a stray Cmd+Q then Return keeps it open.
        let quit = alert.addButton(withTitle: "Quit")
        let cancel = alert.addButton(withTitle: "Cancel")
        quit.keyEquivalent = ""
        cancel.keyEquivalent = "\r"
        alert.window.level = .modalPanel
        return alert.runModal() == .alertFirstButtonReturn ? .terminateNow : .terminateCancel
    }

    func windowDidResignKey(_ notification: Notification) {
        // Keep it open while its own popover or menu has focus.
        DispatchQueue.main.async { [weak self] in
            guard let self, self.panel.isVisible else { return }
            if let key = NSApp.keyWindow, key !== self.panel, key.parent === self.panel || NSApp.isActive {
                return
            }
            self.hide()
        }
    }
}

/// The menu bar glyph: a short bar over an open tray, like the one Claude
/// uses for Projects. Drawn by hand as a template image so macOS tints it
/// for light and dark menu bars.
enum MenuBarIcon {
    static let image: NSImage = {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: true) { _ in
            NSColor.black.setStroke()
            let line: CGFloat = 1.6
            // The bar on top.
            let bar = NSBezierPath()
            bar.lineWidth = 2.0
            bar.lineCapStyle = .round
            bar.move(to: NSPoint(x: 5.8, y: 3.4))
            bar.line(to: NSPoint(x: 12.2, y: 3.4))
            bar.stroke()
            // The tray: a trapezium, wider at the top, every corner rounded.
            let tray = NSBezierPath()
            tray.lineWidth = line
            tray.lineJoinStyle = .round
            let tl = NSPoint(x: 2.6, y: 7.0), tr = NSPoint(x: 15.4, y: 7.0)
            let br = NSPoint(x: 13.6, y: 15.4), bl = NSPoint(x: 4.4, y: 15.4)
            let corners = [tl, tr, br, bl]
            let radius: CGFloat = 1.8
            func toward(_ from: NSPoint, _ to: NSPoint, _ d: CGFloat) -> NSPoint {
                let dx = to.x - from.x, dy = to.y - from.y
                let len = max((dx * dx + dy * dy).squareRoot(), 0.001)
                return NSPoint(x: from.x + dx / len * d, y: from.y + dy / len * d)
            }
            for i in 0..<4 {
                let prev = corners[(i + 3) % 4], here = corners[i], next = corners[(i + 1) % 4]
                let start = toward(here, prev, radius), end = toward(here, next, radius)
                if i == 0 { tray.move(to: start) } else { tray.line(to: start) }
                tray.curve(to: end, controlPoint1: here, controlPoint2: here)
            }
            tray.close()
            tray.stroke()
            return true
        }
        image.isTemplate = true
        return image
    }()
}

/// The solid black panel: rounded, with a hairline edge.
struct BlackPanel<Content: View>: View {
    @ViewBuilder var content: Content
    private let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)

    var body: some View {
        content
            .background(Color.black)
            .clipShape(shape)
            .overlay(shape.strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
    }
}

@Observable
final class SlideState {
    /// 0 hidden off the left edge, 1 fully in.
    var progress: CGFloat = 0
}

/// Moves its content in from the left edge as progress goes 0 → 1.
struct SlidingPanel<Content: View>: View {
    let state: SlideState
    let travel: CGFloat
    @ViewBuilder var content: Content

    var body: some View {
        content.offset(x: -(1 - state.progress) * travel)
    }
}
