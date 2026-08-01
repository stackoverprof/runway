import SwiftUI
import AppKit

enum FeedTab: String, CaseIterable, Codable {
    case runway = "Runway"
    case feeds = "Feeds"
    case pullRequests = "Pulls"

    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        // Preserve workspaces saved before Merge moved into Feeds and the old
        // Posts or Notes tab was replaced by PR.
        if value == "Merge" {
            self = .feeds
        } else if value == "Posts" || value == "Notes" || value == "PR" {
            self = .pullRequests
        } else {
            self = FeedTab(rawValue: value) ?? .feeds
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

/// App-wide state + actions for the agent list. Owned here (not in a view) so the
/// app-level keyboard monitor can drive it even while a terminal has focus.
@MainActor @Observable final class Workspace {
    static let shared = Workspace()

    var boxes: [AgentBox] = [AgentBox(name: "agent1")]
    /// Repository currently projected into the right pane. Boxes belonging to
    /// other repositories remain mounted so their terminal sessions keep running.
    var activeFocusRepository: String?
    /// The box the user last focused (click or keyboard). Drives the focus glow,
    /// the accordion's larger share, and the solo target.
    var focusedID: UUID?
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
    /// Incremented by the app-level ⌘F handler so the active left pane can
    /// toggle its tab-specific search UI.
    var findRequestID = 0
    /// Set by the QuickTerminal so the key monitor can focus it (⌘← when open).
    @ObservationIgnored var focusQuick: (() -> Void)?
    /// Set by the QuickTerminal: reports whether its surface is the window's
    /// first responder right now.
    @ObservationIgnored var quickHasKeyboard: (() -> Bool)?

    /// True while the user is typing into the quick terminal. Background work
    /// (Focus-board reconciliation, a terminal surface mounting) must never pull
    /// the keyboard out from under it.
    var isQuickTerminalFocused: Bool {
        quickVisible && quickHasKeyboard?() == true
    }

    /// Width of the left pane (the split divider position).
    var leftWidth: CGFloat = 460
    /// Temporarily lifts the left pane so its actively dragged Focus card can
    /// cross pane boundaries without lifting ordinary left-pane content.
    var isFocusCardDragging = false
    /// Once the Runway board has loaded, Focus is the sole owner of right-pane boxes.
    var focusBoardControlsBoxes = false

    /// True while the window is full screen (no traffic lights → less top inset).
    var isFullScreen = false

    /// NSEvent.timestamp of the last terminal scroll we forwarded — throttles the
    /// dense trackpad precise-scroll stream so mouse-reporting TUIs don't overshoot.
    @ObservationIgnored var lastTerminalScrollTS: TimeInterval = 0

    /// Last raw control-file contents seen per box, so we only apply changes (and
    /// don't clobber the user's UI edits with a stale file).
    private var lastControl: [UUID: String] = [:]
    @ObservationIgnored private var focusedBoxByRepository: [String: UUID] = [:]
    private var lastSaved: Data?
    /// False until the first control-file poll completes, so adopting agents'
    /// pre-existing needs-action state on launch doesn't fire a burst of toasts.
    private var watchReady = false

    @ObservationIgnored private var dirWatcher: DispatchSourceFileSystemObject?
    @ObservationIgnored private var dirDescriptor: Int32 = -1

    init() {
        load()
        for index in boxes.indices {
            guard let repository = boxes[index].focusRepository else { continue }
            boxes[index].cwd = GitHubFeed.shared.localPath(for: repository)
        }
        activeFocusRepository = GitHubFeed.shared.repo.isEmpty
            ? boxes.first?.focusRepository
            : GitHubFeed.shared.repo
        if boxes.contains(where: { $0.focusRepository != nil }) {
            focusBoardControlsBoxes = true
        }
        // Focus the first box on launch so the glow + accordion expansion match
        // where the keyboard actually lands (the terminal that auto-focuses).
        focusedID = activeBoxes.first?.id
        if let activeFocusRepository, let focusedID {
            focusedBoxByRepository[activeFocusRepository] = focusedID
        }
        // Quitting kills the sessions, so reopen each restored agent into the
        // configured command (e.g. claude) too, not just ⌘N-created ones.
        let cmd = SettingsKey.configuredAgentCommand
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
        quickPinned = s.quickPinned ?? false
        selectedTab = s.selectedTab ?? .feeds
        lastSaved = data
    }

    /// Write current layout to disk if it changed. Cheap enough to call on the poll tick.
    func saveIfNeeded() {
        let snapshot = Persisted(boxes: boxes, leftWidth: leftWidth,
                                 quickHeight: quickHeight, accordion: true,
                                 quickPinned: quickPinned, selectedTab: selectedTab)
        guard let data = try? JSONEncoder().encode(snapshot), data != lastSaved else { return }
        lastSaved = data
        try? data.write(to: Self.stateFile)
    }

    func toggleQuick() {
        quickVisible.toggle()
        // Closing a pinned quick terminal also drops the pin: pinning is a
        // "keep this open" request, so dismissing it retires that request and
        // the next open behaves normally (auto-hide when it loses focus).
        if !quickVisible { quickPinned = false }
    }

    func requestFind() { findRequestID &+= 1 }

    var focusedIndex: Int? { boxes.firstIndex { $0.id == focusedID } }

    var activeBoxes: [AgentBox] {
        guard focusBoardControlsBoxes, let activeFocusRepository else { return boxes }
        return boxes.filter { $0.focusRepository == activeFocusRepository }
    }

    func isBoxInActiveRepository(_ box: AgentBox) -> Bool {
        !focusBoardControlsBoxes || box.focusRepository == activeFocusRepository
    }

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
            if boxes[i].focusIssueNumber == nil,
               let name = (json["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
               !name.isEmpty {
                boxes[i].name = String(name.prefix(40))
            }
            if boxes[i].focusIssueNumber == nil,
               let desc = json["description"] as? String {
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
        guard !focusBoardControlsBoxes else { return }
        var box = AgentBox(name: "agent\(boxes.count + 1)")
        let cmd = SettingsKey.configuredAgentCommand
        if !cmd.isEmpty { box.autorun = cmd }   // run it as the shell starts
        boxes.append(box)
        setFocus(box.id)
    }

    @discardableResult
    func closeFocused() -> Bool {
        guard !focusBoardControlsBoxes else { return true }
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
        let candidates = activeBoxes
        guard !candidates.isEmpty else { return }
        let current = candidates.firstIndex { $0.id == focusedID } ?? 0
        let next = ((current + offset) % candidates.count + candidates.count) % candidates.count
        setFocus(candidates[next].id)
    }

    func focus(index: Int) {
        let candidates = activeBoxes
        guard candidates.indices.contains(index) else { return }
        setFocus(candidates[index].id)
    }

    func moveFocused(by delta: Int) {
        guard !focusBoardControlsBoxes else { return }
        guard let idx = focusedIndex else { return }
        let target = idx + delta
        guard boxes.indices.contains(target) else { return }
        boxes.swapAt(idx, target)
    }

    func toggleSolo() {
        guard focusedID != nil else { return }
        soloed.toggle()
    }

    /// Set the visual focus and give that box's terminal keyboard focus.
    ///
    /// `moveKeyboard: false` moves the glow and the accordion share only. Use it
    /// for anything the user did not directly ask for, so a background refresh
    /// never interrupts typing somewhere else in the window.
    func setFocus(_ id: UUID?, moveKeyboard: Bool = true) {
        focusedID = id
        if let id,
           let repository = boxes.first(where: { $0.id == id })?.focusRepository {
            focusedBoxByRepository[repository] = id
        }
        guard moveKeyboard else { return }
        TerminalRegistry.shared.focusTerminal(id)
    }

    /// Reconcile one repository's Focus board without disturbing terminal
    /// sessions owned by other repositories.
    func syncFocusBoard(issues: [AssignedIssue], repository: String) {
        let wasFocusControlled = focusBoardControlsBoxes
        focusBoardControlsBoxes = true
        let previousBoxes = boxes
        if let activeFocusRepository, let focusedID,
           previousBoxes.contains(where: {
               $0.id == focusedID && $0.focusRepository == activeFocusRepository
           }) {
            focusedBoxByRepository[activeFocusRepository] = focusedID
        }

        let previousRepositoryBoxes = previousBoxes.filter {
            $0.focusRepository == repository
        }
        let previousRepositoryFocusID = focusedBoxByRepository[repository]
            ?? focusedID.flatMap { id in
                previousRepositoryBoxes.contains(where: { $0.id == id }) ? id : nil
            }
        let previousFocusedIndex = previousRepositoryFocusID.flatMap { id in
            previousRepositoryBoxes.firstIndex { $0.id == id }
        } ?? 0
        let reconciliation = FocusBoxReconciler.reconcile(
            previousBoxes: previousBoxes,
            issues: issues,
            repository: repository,
            workingDirectory: GitHubFeed.shared.localPath(for: repository),
            command: SettingsKey.configuredAgentCommand,
            retainUnmanagedBoxes: wasFocusControlled
        )
        let nextRepositoryBoxes = reconciliation.repositoryBoxes

        for removed in reconciliation.removedBoxes {
            TerminalRegistry.shared.unregister(id: removed.id)
            AgentControl.cleanup(removed.id)
            lastControl[removed.id] = nil
        }
        boxes = reconciliation.boxes
        activeFocusRepository = repository

        if nextRepositoryBoxes.isEmpty {
            setFocus(nil)
            soloed = false
        } else {
            let nextFocusID: UUID
            if let previousRepositoryFocusID,
               nextRepositoryBoxes.contains(where: { $0.id == previousRepositoryFocusID }) {
                nextFocusID = previousRepositoryFocusID
            } else {
                nextFocusID = nextRepositoryBoxes[
                    min(previousFocusedIndex, nextRepositoryBoxes.count - 1)
                ].id
            }
            // This runs on every background issue refresh, so it must be inert
            // for the keyboard. Only hand the keyboard over when the focused box
            // genuinely changed, and never while the quick terminal has it.
            // Otherwise a routine poll yanks the caret mid-keystroke.
            setFocus(
                nextFocusID,
                moveKeyboard: nextFocusID != focusedID && !isQuickTerminalFocused
            )
        }
        saveIfNeeded()
    }
}

struct FocusBoxReconciliation {
    let boxes: [AgentBox]
    let repositoryBoxes: [AgentBox]
    let removedBoxes: [AgentBox]
}

enum FocusBoxReconciler {
    static func reconcile(
        previousBoxes: [AgentBox],
        issues: [AssignedIssue],
        repository: String,
        workingDirectory: String?,
        command: String,
        retainUnmanagedBoxes: Bool
    ) -> FocusBoxReconciliation {
        let previousRepositoryBoxes = previousBoxes.filter {
            $0.focusRepository == repository
        }
        var usedIDs = Set<UUID>()
        var repositoryBoxes: [AgentBox] = []

        for issue in issues {
            if var existing = previousRepositoryBoxes.first(where: {
                $0.focusIssueNumber == issue.number
            }) {
                existing.name = issue.title
                existing.cwd = workingDirectory
                repositoryBoxes.append(existing)
                usedIDs.insert(existing.id)
            } else {
                var box = AgentBox(
                    name: issue.title,
                    detail: "",
                    cwd: workingDirectory,
                    focusRepository: repository,
                    focusIssueNumber: issue.number
                )
                if !command.isEmpty { box.autorun = command }
                repositoryBoxes.append(box)
                usedIDs.insert(box.id)
            }
        }

        let removedRepositoryBoxes = previousRepositoryBoxes.filter {
            !usedIDs.contains($0.id)
        }
        let removedUnmanagedBoxes = retainUnmanagedBoxes
            ? []
            : previousBoxes.filter { $0.focusRepository == nil }
        let retainedBoxes = previousBoxes.filter {
            $0.focusRepository != repository
                && (retainUnmanagedBoxes || $0.focusRepository != nil)
        }
        return FocusBoxReconciliation(
            boxes: retainedBoxes + repositoryBoxes,
            repositoryBoxes: repositoryBoxes,
            removedBoxes: removedRepositoryBoxes + removedUnmanagedBoxes
        )
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
