import SwiftUI
import AppKit

enum FeedTab: String, CaseIterable, Codable {
    case feeds = "Feeds"
    case merge = "Merge"
    case posts = "Posts"
}

/// App-wide state + actions for the agent list. Owned here (not in a view) so the
/// app-level keyboard monitor can drive it even while a terminal has focus.
@MainActor @Observable final class Workspace {
    static let shared = Workspace()

    var boxes: [AgentBox] = [AgentBox(name: "agent1")]
    /// The box the user last focused (click or keyboard). Drives the focus glow,
    /// the accordion's larger share, and the solo target.
    var focusedID: UUID?
    /// Accordion: no scroll, boxes split the height, focused box larger.
    var accordion = false
    /// Solo / zoom: show only the focused box, filling the pane.
    var soloed = false

    /// Quick terminal: a persistent background terminal overlaid bottom-left,
    /// toggled with ⌘⌥Q. `quickHeight == 0` means "use 50% of the pane".
    var quickVisible = false
    var quickPinned = false
    var quickHeight: CGFloat = 0
    var quickState: AgentState = .idle
    /// The currently selected feed tab in the left pane
    var selectedTab: FeedTab = .feeds
    /// Set by the QuickTerminal so the key monitor can focus it (⌘← when open).
    @ObservationIgnored var focusQuick: (() -> Void)?

    /// Width of the left pane (the split divider position).
    var leftWidth: CGFloat = 460

    /// True while the window is full screen (no traffic lights → less top inset).
    var isFullScreen = false

    /// NSEvent.timestamp of the last terminal scroll we forwarded — throttles the
    /// dense trackpad precise-scroll stream so mouse-reporting TUIs don't overshoot.
    @ObservationIgnored var lastTerminalScrollTS: TimeInterval = 0

    /// Last raw control-file contents seen per box, so we only apply changes (and
    /// don't clobber the user's UI edits with a stale file).
    private var lastControl: [UUID: String] = [:]
    private var lastSaved: Data?
    /// False until the first control-file poll completes, so adopting agents'
    /// pre-existing needs-action state on launch doesn't fire a burst of toasts.
    private var watchReady = false

    @ObservationIgnored private var dirWatcher: DispatchSourceFileSystemObject?
    @ObservationIgnored private var dirDescriptor: Int32 = -1

    init() {
        load()
        // Focus the first box on launch so the glow + accordion expansion match
        // where the keyboard actually lands (the terminal that auto-focuses).
        focusedID = boxes.first?.id
        // Quitting kills the sessions, so reopen each restored agent into the
        // configured command (e.g. claude) too, not just ⌘N-created ones.
        let cmd = (UserDefaults.standard.string(forKey: SettingsKey.initialCommand) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !cmd.isEmpty { for i in boxes.indices { boxes[i].autorun = cmd } }
    }

    // MARK: Persistence

    private struct Persisted: Codable {
        var boxes: [AgentBox]
        var leftWidth: CGFloat
        var quickHeight: CGFloat
        var accordion: Bool
        var quickPinned: Bool?
        var selectedTab: FeedTab?
    }

    private static var stateFile: URL { AgentControl.supportDir.appendingPathComponent("workspace.json") }

    private func load() {
        guard let data = try? Data(contentsOf: Self.stateFile),
              let s = try? JSONDecoder().decode(Persisted.self, from: data) else { return }
        if !s.boxes.isEmpty { boxes = s.boxes }
        leftWidth = s.leftWidth
        quickHeight = s.quickHeight
        accordion = s.accordion
        quickPinned = s.quickPinned ?? false
        selectedTab = s.selectedTab ?? .feeds
        lastSaved = data
    }

    /// Write current layout to disk if it changed. Cheap enough to call on the poll tick.
    func saveIfNeeded() {
        let snapshot = Persisted(boxes: boxes, leftWidth: leftWidth,
                                 quickHeight: quickHeight, accordion: accordion,
                                 quickPinned: quickPinned, selectedTab: selectedTab)
        guard let data = try? JSONEncoder().encode(snapshot), data != lastSaved else { return }
        lastSaved = data
        try? data.write(to: Self.stateFile)
    }

    func toggleQuick() { quickVisible.toggle() }

    var focusedIndex: Int? { boxes.firstIndex { $0.id == focusedID } }

    // MARK: Agent control channel

    /// Poll each box's control file and apply name/description/state the agent wrote.
    func startAgentWatch() {
        let dirPath = AgentControl.controlDir.path
        dirDescriptor = open(dirPath, O_EVTONLY)
        if dirDescriptor >= 0 {
            let source = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: dirDescriptor,
                eventMask: .write,
                queue: DispatchQueue.main
            )
            source.setEventHandler { [weak self] in
                guard let self else { return }
                self.pollControlFiles()
                self.saveIfNeeded()
            }
            source.setCancelHandler { [weak self] in
                guard let fd = self?.dirDescriptor else { return }
                close(fd)
            }
            dirWatcher = source
            source.resume()
        }

        Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                pollControlFiles()
                saveIfNeeded()
                watchReady = true   // subsequent polls fire transition toasts
            }
        }
    }

    deinit {
        dirWatcher?.cancel()
    }

    private func pollControlFiles() {
        for i in boxes.indices {
            let id = boxes[i].id

            // Working directory the box's shell recorded — persisted so the agent
            // reopens in the same folder after a relaunch.
            if let cwdData = try? Data(contentsOf: AgentControl.cwdFile(for: id)),
               let dir = String(data: cwdData, encoding: .utf8)?
                   .trimmingCharacters(in: .whitespacesAndNewlines),
               !dir.isEmpty, dir != boxes[i].cwd {
                boxes[i].cwd = dir
            }

            guard let data = try? Data(contentsOf: AgentControl.file(for: id)),
                  let raw = String(data: data, encoding: .utf8) else { continue }
            if lastControl[id] == raw { continue }   // unchanged → skip
            lastControl[id] = raw
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
            if let name = (json["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
               !name.isEmpty {
                boxes[i].name = String(name.prefix(40))
            }
            if let desc = json["description"] as? String {
                boxes[i].detail = String(desc.prefix(40))
            }
            if let state = json["state"] as? String {
                let next = AgentState(control: state)
                if watchReady, next == .needsAction, boxes[i].state != .needsAction {
                    if NSApp.isActive {
                        // App is active: only play sound, no native banner (header will pulse in UI).
                        if UserDefaults.standard.bool(forKey: SettingsKey.soundEnabled) {
                            RunwayNotificationManager.playSelectedSound()
                        }
                    } else {
                        // App is backgrounded: show native OS notification banner with sound.
                        RunwayNotificationManager.shared.show("\(boxes[i].name) needs your attention", sound: true)
                    }
                }
                boxes[i].state = next
            }
        }
        
        // Poll quick terminal's control file
        let quickID = QuickTerminal.quickBoxID
        if let data = try? Data(contentsOf: AgentControl.file(for: quickID)),
           let raw = String(data: data, encoding: .utf8) {
            if lastControl[quickID] != raw {
                lastControl[quickID] = raw
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let state = json["state"] as? String {
                    let next = AgentState(control: state)
                    if watchReady, next == .needsAction, quickState != .needsAction {
                        quickVisible = true
                        if NSApp.isActive {
                            if UserDefaults.standard.bool(forKey: SettingsKey.soundEnabled) {
                                RunwayNotificationManager.playSelectedSound()
                            }
                        } else {
                            RunwayNotificationManager.shared.show("Quick terminal needs your attention", sound: true)
                        }
                    }
                    quickState = next
                }
            }
        } else {
            quickState = .idle
        }
    }

    // MARK: Actions (driven by the keyboard monitor + clicks)

    func newBox() {
        var box = AgentBox(name: "agent\(boxes.count + 1)")
        let cmd = (UserDefaults.standard.string(forKey: SettingsKey.initialCommand) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !cmd.isEmpty { box.autorun = cmd }   // run it as the shell starts
        boxes.append(box)
        setFocus(box.id)
    }

    @discardableResult
    func closeFocused() -> Bool {
        guard let idx = focusedIndex else { return false }
        let removed = boxes.remove(at: idx)
        TerminalRegistry.shared.unregister(id: removed.id)
        AgentControl.cleanup(removed.id)
        lastControl[removed.id] = nil
        if boxes.isEmpty {
            focusedID = nil
            soloed = false
        } else {
            setFocus(boxes[min(idx, boxes.count - 1)].id)
        }
        return true
    }

    func focus(offset: Int) {
        guard !boxes.isEmpty else { return }
        let current = focusedIndex ?? 0
        let next = ((current + offset) % boxes.count + boxes.count) % boxes.count
        setFocus(boxes[next].id)
    }

    func focus(index: Int) {
        guard boxes.indices.contains(index) else { return }
        setFocus(boxes[index].id)
    }

    func moveFocused(by delta: Int) {
        guard let idx = focusedIndex else { return }
        let target = idx + delta
        guard boxes.indices.contains(target) else { return }
        boxes.swapAt(idx, target)
    }

    func toggleAccordion() {
        // Choosing a base layout un-zooms.
        soloed = false
        accordion.toggle()
    }

    func toggleSolo() {
        // Solo is an overlay on the current mode; toggling it preserves
        // `accordion`, so exiting solo returns to whatever mode you were in.
        guard focusedID != nil else { return }
        soloed.toggle()
    }

    /// Set the visual focus and give that box's terminal keyboard focus.
    func setFocus(_ id: UUID?) {
        focusedID = id
        TerminalRegistry.shared.focusTerminal(id)
    }
}

/// Maps box ids to their terminal NSViews (both directions) so clicks resolve to
/// a box, and keyboard navigation can make a box's terminal first responder.
@MainActor final class TerminalRegistry {
    static let shared = TerminalRegistry()
    private var viewToID: [ObjectIdentifier: UUID] = [:]
    private var idToView: [UUID: NSView] = [:]
    private var initSentinel = false

    func register(_ view: NSView, id: UUID) {
        viewToID[ObjectIdentifier(view)] = id
        idToView[id] = view
    }

    func unregister(id: UUID) {
        if let view = idToView[id] { viewToID.removeValue(forKey: ObjectIdentifier(view)) }
        idToView.removeValue(forKey: id)
    }

    /// Walks up from `view` to find the first registered terminal and its box id.
    func boxID(under view: NSView) -> UUID? {
        var node: NSView? = view
        while let cur = node {
            if let id = viewToID[ObjectIdentifier(cur)] { return id }
            node = cur.superview
        }
        return nil
    }

    func focusTerminal(_ id: UUID?) {
        guard let id, let view = idToView[id] else { return }
        view.window?.makeFirstResponder(view)
    }
}
