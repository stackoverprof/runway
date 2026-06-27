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
            RunwayWindowRegistry.shared.unregister(for: self.window)
        }
    }

    func registerIfPossible() {
        guard let context else { return }
        RunwayWindowRegistry.shared.register(context, for: window)
    }
}
