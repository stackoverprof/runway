import SwiftUI
import AppKit

enum FeedTab: String, CaseIterable, Codable {
    case runway = "Runway"
    case feeds = "Feeds"
    case pullRequests = "Pulls"

    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        // Workspaces saved by earlier versions name tabs this one no longer
        // has, Runway and Merge among them; they all open on Feeds.
        if value == "Posts" || value == "Notes" || value == "PR" || value == "Pulls" {
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

/// What the keyboard can ask of the ATC panel's tabs.
enum QuickTerminalTabAction: Equatable {
    case new
    case close
    case select(Int)
    case selectRoot(String)
    case cycle(Int)
}

/// One such ask, carried with an id so the same action twice in a row still
/// arrives twice.
struct QuickTerminalTabRequest: Equatable {
    let id = UUID()
    let action: QuickTerminalTabAction
}

/// Stepping through a tab's own options from the keyboard.
enum SubtabNavigation {
    /// Wraps at both ends, so ⌘⌥] past the last option returns to the first.
    /// `nil` when there is nothing to step through.
    static func index(from current: Int, by delta: Int, count: Int) -> Int? {
        guard count > 1 else { return nil }
        return ((current + delta) % count + count) % count
    }
}

/// Open / Closed inside the Runway tab.
enum RunwayIssueTab: String, CaseIterable, Identifiable {
    case open = "Open"
    case closed = "Closed"

    var id: String { rawValue }
}

/// Everything / merges-only inside the Feeds tab.
enum FeedFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case merges = "Merges"

    var id: String { rawValue }
    var showsMergesOnly: Bool { self == .merges }
}

/// The window the Pulls tab counts over.
enum PRTimeframe: String, CaseIterable, Identifiable {
    case oneDay = "24h"
    case sevenDays = "7d"
    case thirtyDays = "30d"
    case monthToDate = "MTD"
    case yearToDate = "YTD"

    var id: String { rawValue }

    /// Pulls opens on the timeframe chosen in Settings, whatever it was left on
    /// last time. Month to date unless that was changed.
    static var initial: PRTimeframe { SettingsKey.configuredPullsTimeframe() }

    func startDate(now: Date = Date(), calendar: Calendar = .current) -> Date {
        switch self {
        case .oneDay:
            return now.addingTimeInterval(-86_400)
        case .sevenDays:
            return now.addingTimeInterval(-7 * 86_400)
        case .thirtyDays:
            return now.addingTimeInterval(-30 * 86_400)
        case .monthToDate:
            return calendar.dateInterval(of: .month, for: now)?.start ?? now
        case .yearToDate:
            return calendar.dateInterval(of: .year, for: now)?.start ?? now
        }
    }
}

/// What one window is showing: the tab in front, that tab's own option, and
/// the requests the keyboard and `runway://` links raise against it.
@MainActor @Observable final class Workspace {
    var selectedTab: FeedTab = .feeds
    var runwayIssueTab: RunwayIssueTab = .open
    var feedFilter: FeedFilter = .all
    /// How wide the activity pane is; the rest of the window is the open space
    /// beside it.
    var leftWidth: CGFloat = 520
    var prTimeframe: PRTimeframe = .initial
    var isFullScreen = false

    // MARK: ATC panel
    //
    // One agent above every flight, in a panel over the activity pane: the
    // quick terminal, with tabs for as many controllers as you keep open.
    var quickVisible = false
    var quickPinned = false
    var quickHeight: CGFloat = 0
    var quickState: AgentState = .idle
    var quickTabStates: [String: AgentState] = [:]
    private(set) var quickTabRequest: QuickTerminalTabRequest?
    /// Set by the panel so the rest of the app can hand it the keyboard.
    @ObservationIgnored var focusQuick: (() -> Void)?
    @ObservationIgnored var quickHasKeyboard: (() -> Bool)?
    /// The terminal that had the keyboard before the panel took it.
    @ObservationIgnored var focusedID: UUID?
    @ObservationIgnored var lastTerminalScrollTS: TimeInterval = 0

    /// Whether the ATC panel holds the keyboard right now.
    var isQuickTerminalFocused: Bool {
        quickVisible && quickHasKeyboard?() == true
    }

    func setFocus(_ id: UUID?) {
        focusedID = id
    }

    func toggleQuick() {
        quickVisible.toggle()
        if quickVisible { focusQuick?() }
    }

    func requestQuickTabAction(_ action: QuickTerminalTabAction) {
        quickTabRequest = QuickTerminalTabRequest(action: action)
    }

    /// Watch what the controllers report. Each writes a small control file as
    /// it works, which is where the dot on its tab comes from.
    func startAgentWatch() {
        let path = AgentControl.controlDir.path
        controlDescriptor = open(path, O_EVTONLY)
        if controlDescriptor >= 0 {
            let source = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: controlDescriptor,
                eventMask: .write,
                queue: DispatchQueue.main
            )
            source.setEventHandler { [weak self] in
                self?.pollControlFiles()
            }
            source.setCancelHandler { [weak self] in
                guard let descriptor = self?.controlDescriptor else { return }
                close(descriptor)
            }
            controlWatcher = source
            source.resume()
        }

        // Backstop, for anything that writes a control file without touching
        // the directory itself.
        Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                pollControlFiles()
                saveIfNeeded()
            }
        }
    }

    private func pollControlFiles() {
        let roots = QuickTerminalSession.tabRoots()
        var states: [String: AgentState] = [:]
        for root in roots {
            let id = QuickTerminalSession.boxID(root: root)
            guard let data = try? Data(contentsOf: AgentControl.file(for: id)),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let state = json["state"] as? String else { continue }
            states[root] = AgentState(control: state)
        }
        if states != quickTabStates { quickTabStates = states }
        let selected = QuickTerminalSession.selectedRoot()
        let next = quickTabStates[selected] ?? .idle
        if next != quickState { quickState = next }
    }

    /// The feed this window reads. Each window can follow its own repository.
    @ObservationIgnored var repositoryFeed: GitHubFeed?

    /// Bumped to ask the view for something; the view watches the id, not a
    /// flag, so the same request twice in a row still arrives twice.
    private(set) var findRequestID = 0
    private(set) var repoPickerRequestID = 0
    private(set) var tabResetRequestID = 0
    private(set) var sourceRefreshRequestID = 0
    private(set) var sourceRefreshTab: FeedTab = .feeds

    @ObservationIgnored private var lastSaved: Data?
    @ObservationIgnored private var controlWatcher: DispatchSourceFileSystemObject?
    @ObservationIgnored private var controlDescriptor: Int32 = -1

    init() { load() }

    deinit { controlWatcher?.cancel() }

    func requestFind() { findRequestID &+= 1 }

    /// Picking the tab you are already on: back to the top, and refetch.
    func requestTabReset() { tabResetRequestID &+= 1 }

    func requestRepoPicker() { repoPickerRequestID &+= 1 }

    /// Refetch one tab's source in place (see `RunwayURLCommand`).
    func requestSourceRefresh(_ tab: FeedTab) {
        sourceRefreshTab = tab
        sourceRefreshRequestID &+= 1
    }

    // MARK: Subtabs

    /// Options the current tab offers below itself, in display order.
    var subtabLabels: [String] {
        switch selectedTab {
        case .runway: RunwayIssueTab.allCases.map(\.rawValue)
        case .feeds: FeedFilter.allCases.map(\.rawValue)
        case .pullRequests: PRTimeframe.allCases.map(\.rawValue)
        }
    }

    var selectedSubtabIndex: Int {
        switch selectedTab {
        case .runway: RunwayIssueTab.allCases.firstIndex(of: runwayIssueTab) ?? 0
        case .feeds: FeedFilter.allCases.firstIndex(of: feedFilter) ?? 0
        case .pullRequests: PRTimeframe.allCases.firstIndex(of: prTimeframe) ?? 0
        }
    }

    func selectSubtab(index: Int) {
        switch selectedTab {
        case .runway:
            guard RunwayIssueTab.allCases.indices.contains(index) else { return }
            runwayIssueTab = RunwayIssueTab.allCases[index]
        case .feeds:
            guard FeedFilter.allCases.indices.contains(index) else { return }
            feedFilter = FeedFilter.allCases[index]
        case .pullRequests:
            guard PRTimeframe.allCases.indices.contains(index) else { return }
            prTimeframe = PRTimeframe.allCases[index]
        }
    }

    func cycleTab(by delta: Int) {
        let tabs = FeedTab.allCases
        guard let index = tabs.firstIndex(of: selectedTab),
              let next = SubtabNavigation.index(
                  from: index,
                  by: delta,
                  count: tabs.count
              ) else { return }
        selectedTab = tabs[next]
    }

    func cycleSubtab(by delta: Int) {
        guard let next = SubtabNavigation.index(
            from: selectedSubtabIndex,
            by: delta,
            count: subtabLabels.count
        ) else { return }
        selectSubtab(index: next)
    }

    // MARK: Persistence

    private struct Persisted: Codable {
        var selectedTab: FeedTab?
        var leftWidth: CGFloat?
        var quickHeight: CGFloat?
        var quickPinned: Bool?
    }

    private static var stateFile: URL {
        RunwayStorage.supportDir.appendingPathComponent("workspace.json")
    }

    private func load() {
        guard let data = try? Data(contentsOf: Self.stateFile),
              let saved = try? JSONDecoder().decode(Persisted.self, from: data) else { return }
        selectedTab = saved.selectedTab ?? .feeds
        leftWidth = saved.leftWidth ?? leftWidth
        quickHeight = saved.quickHeight ?? 0
        quickPinned = saved.quickPinned ?? false
        lastSaved = data
    }

    /// Write the window's state if it changed. Cheap enough for the poll tick.
    func saveIfNeeded() {
        let snapshot = Persisted(
            selectedTab: selectedTab,
            leftWidth: leftWidth,
            quickHeight: quickHeight,
            quickPinned: quickPinned
        )
        guard let data = try? JSONEncoder().encode(snapshot), data != lastSaved else { return }
        lastSaved = data
        try? data.write(to: Self.stateFile)
    }
}
