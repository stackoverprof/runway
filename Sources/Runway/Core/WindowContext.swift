import SwiftUI
import AppKit

@MainActor @Observable final class RunwayWindowContext {
    let workspace = Workspace()
    let githubFeed = GitHubFeed()
    let agentFeed = AgentFeed()
    private var started = false

    func startIfNeeded() {
        guard !started else { return }
        started = true
        workspace.startAgentWatch()
        githubFeed.startPolling()
        agentFeed.startWatching()
    }
}

@MainActor final class RunwayWindowRegistry {
    static let shared = RunwayWindowRegistry()
    private var contexts: [ObjectIdentifier: RunwayWindowContext] = [:]

    func register(_ context: RunwayWindowContext, for window: NSWindow?) {
        guard let window else { return }
        contexts[ObjectIdentifier(window)] = context
    }

    func unregister(for window: NSWindow?) {
        guard let window else { return }
        contexts[ObjectIdentifier(window)] = nil
    }

    func context(for window: NSWindow?) -> RunwayWindowContext? {
        guard let window else { return nil }
        return contexts[ObjectIdentifier(window)]
    }

    func activeContext() -> RunwayWindowContext? {
        context(for: NSApp.keyWindow)
    }
}

struct WindowRegistrationView: NSViewRepresentable {
    let context: RunwayWindowContext

    func makeNSView(context: Context) -> WindowRegistrationNSView {
        let view = WindowRegistrationNSView()
        view.context = self.context
        return view
    }

    func updateNSView(_ nsView: WindowRegistrationNSView, context: Context) {
        nsView.context = self.context
        nsView.registerIfPossible()
    }
}

final class WindowRegistrationNSView: NSView {
    var context: RunwayWindowContext?
    private var closeObserver: NSObjectProtocol?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let closeObserver {
            NotificationCenter.default.removeObserver(closeObserver)
            self.closeObserver = nil
        }
        registerIfPossible()
        guard let window else { return }
        closeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            MainActor.assumeIsolated {
                RunwayWindowRegistry.shared.unregister(for: self.window)
            }
        }
    }

    func registerIfPossible() {
        guard let context else { return }
        RunwayWindowRegistry.shared.register(context, for: window)
    }
}

/// Forces the host NSWindow to drop its titlebar entirely: full-size content
/// view, transparent titlebar background, hidden window title, and repositioned
/// traffic light buttons.
struct WindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { WindowConfigView() }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

final class WindowConfigView: NSView {
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
        syncFullScreen()   // catch launch-into-full-screen (no enter notification fires)

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
        syncFullScreen()
        for type in buttonTypes {
            guard let button = window.standardWindowButton(type),
                  let origin = defaultOrigins[type] else { continue }
            // Clamp Y so we never push a button off the bottom of its container.
            let y = max(3, origin.y - insetY)
            button.setFrameOrigin(NSPoint(x: origin.x + insetX, y: y))
        }
    }

    /// Mirror the window's real full-screen state into the workspace. The
    /// enter/exit notifications don't fire when the app launches already in full
    /// screen, which left the header using the windowed (traffic-light) inset.
    private func syncFullScreen() {
        guard let window else { return }
        let fs = window.styleMask.contains(.fullScreen)
        MainActor.assumeIsolated {
            if let workspace = RunwayWindowRegistry.shared.context(for: window)?.workspace,
               workspace.isFullScreen != fs {
                workspace.isFullScreen = fs
            }
        }
    }

    deinit { NotificationCenter.default.removeObserver(self) }
}
