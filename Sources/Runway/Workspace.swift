import SwiftUI
import AppKit

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
    var quickHeight: CGFloat = 0

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

    private init() {
        load()
        // Focus the first box on launch so the glow + accordion expansion match
        // where the keyboard actually lands (the terminal that auto-focuses).
        focusedID = boxes.first?.id
    }

    // MARK: Persistence

    private struct Persisted: Codable {
        var boxes: [AgentBox]
        var leftWidth: CGFloat
        var quickHeight: CGFloat
        var accordion: Bool
    }

    private static var stateFile: URL { AgentControl.supportDir.appendingPathComponent("workspace.json") }

    private func load() {
        guard let data = try? Data(contentsOf: Self.stateFile),
              let s = try? JSONDecoder().decode(Persisted.self, from: data) else { return }
        if !s.boxes.isEmpty { boxes = s.boxes }
        leftWidth = s.leftWidth
        quickHeight = s.quickHeight
        accordion = s.accordion
        lastSaved = data
    }

    /// Write current layout to disk if it changed. Cheap enough to call on the poll tick.
    func saveIfNeeded() {
        let snapshot = Persisted(boxes: boxes, leftWidth: leftWidth,
                                 quickHeight: quickHeight, accordion: accordion)
        guard let data = try? JSONEncoder().encode(snapshot), data != lastSaved else { return }
        lastSaved = data
        try? data.write(to: Self.stateFile)
    }

    func toggleQuick() { quickVisible.toggle() }

    var focusedIndex: Int? { boxes.firstIndex { $0.id == focusedID } }

    // MARK: Agent control channel

    /// Poll each box's control file and apply name/description/state the agent wrote.
    func startAgentWatch() {
        Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 400_000_000)
                pollControlFiles()
                saveIfNeeded()
                watchReady = true   // subsequent polls fire transition toasts
            }
        }
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
                    ToastCenter.shared.show("\(boxes[i].name) needs your attention",
                                            icon: "exclamationmark.bubble.fill",
                                            tint: Color(red: 0.91, green: 0.62, blue: 0.20),
                                            sound: true)
                }
                boxes[i].state = next
            }
        }
    }

    // MARK: Actions (driven by the keyboard monitor + clicks)

    func newBox() {
        let box = AgentBox(name: "agent\(boxes.count + 1)")
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
    private init() {}

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
