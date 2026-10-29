import Foundation

struct AssignedIssue: Codable, Identifiable, Sendable, Equatable {
    let number: Int
    var title: String
    var state: String
    var closedAt: Date?
    let createdAt: Date?
    let updatedAt: Date?
    let url: URL

    var id: Int { number }
    var isClosed: Bool { state == "CLOSED" }

    static func matchesSearchQuery(
        _ query: String,
        issue: AssignedIssue,
        repositoryName: String
    ) -> Bool {
        let searchableText = "\(GitHubNumber.reference(issue.number)) \(issue.title) \(repositoryName)"
        return SearchText.containsAllTokens(of: query, in: searchableText)
    }
}

enum AssignedIssueLane: String, Codable, Hashable {
    case focus
    case open
    case closed
}

private struct IssueBoardCommand: Codable {
    let id: String
    let action: String
    let repository: String
    /// The clone whose board the command is for, by folder name. Empty or
    /// absent means whichever clone of the repository is on screen.
    let clone: String?
    let issueNumber: Int?
    let destination: AssignedIssueLane?
    let beforeNumber: Int?
    let lane: AssignedIssueLane?
}

private struct IssueBoardResponse: Codable {
    let success: Bool
    let error: String?
    /// The clone on screen; each Focus card's agent is `<clone>-<number>`.
    let clone: String?
    let open: [AssignedIssue]
    let focus: [AssignedIssue]
    let closed: [AssignedIssue]
}

/// A Focus reel changed on a board that is not on screen, so Workspace can
/// open or close that board's terminals without switching the view.
struct OffScreenFocusChange {
    let repository: String
    let checkout: String?
    let issues: [AssignedIssue]
}

extension Notification.Name {
    static let assignedIssueBacklogOrderReset = Notification.Name(
        "runway.assignedIssueBacklogOrderReset"
    )
}

@MainActor @Observable final class AssignedIssues {
    private(set) var issues: [AssignedIssue] = []
    private(set) var loading = false
    private(set) var error: String?
    private(set) var hasSnapshot = false
    private(set) var focusReel = FocusReel(visibleCount: SettingsKey.configuredFocusVisibleCount())
    private(set) var openIssueNumbers: [Int] = []
    private(set) var closedIssueNumbers: [Int] = []

    private var loadedRepository: String?
    /// The Focus board on screen: the repository, or one clone of it.
    private var loadedBoard: String?
    private var loadTask: Task<Void, Never>?
    private var loadTaskRepository: String?
    @ObservationIgnored private var snapshots = AssignedIssues.readSnapshots()
    @ObservationIgnored private var pendingRenameTitles: [String: [Int: String]] = [:]
    /// Set by the left pane: applies an off-screen board's new Focus reel to
    /// its terminals.
    @ObservationIgnored var onOffScreenFocusChange: ((OffScreenFocusChange) -> Void)?
    private static let focusedIssuesKey = "runway.focusedAssignedIssueNumbers.v2"
    /// Paginated boards, read once per repository to migrate into the reel.
    private static let legacyFocusBoardsKey = "runway.focusBoards.v1"
    private static let focusReelKey = "runway.focusReel.v1"
    private static let backlogOrderKey = "runway.assignedIssueBacklogOrder.v2"
    private static var snapshotFile: URL {
        AgentControl.supportDir.appendingPathComponent("assigned-issues-cache.json")
    }

    var open: [AssignedIssue] {
        let focused = focusReel.allSet
        return orderedIssues(openIssueNumbers)
            .filter { !$0.isClosed && !focused.contains($0.number) }
    }

    var closed: [AssignedIssue] {
        let focused = focusReel.allSet
        return orderedIssues(closedIssueNumbers)
            .filter { $0.isClosed && !focused.contains($0.number) }
    }

    /// Issues in the window, the ones whose terminals are on screen.
    var focusedIssueNumbers: [Int] { focusReel.visible }
    var allFocusedIssueNumbers: [Int] { focusReel.issues }
    var allFocused: [AssignedIssue] { orderedIssues(focusReel.issues) }
    var hiddenAboveCount: Int { focusReel.hiddenAbove }
    var hiddenBelowCount: Int { focusReel.hiddenBelow }
    var firstHiddenBelowFocusIssue: Int? { focusReel.firstHiddenBelow }

    var focused: [AssignedIssue] {
        orderedIssues(focusedIssueNumbers)
    }

    /// Whether Focus takes one more issue under the configured limit.
    var canAddToFocus: Bool {
        FocusReel.canAdd(count: focusReel.count, limit: SettingsKey.configuredFocusLimit())
    }

    func focusContains(_ issueNumber: Int) -> Bool {
        focusReel.contains(issueNumber)
    }

    /// Slides the window. Never a Focus entry or exit, so nothing is logged.
    @discardableResult
    func shiftFocusWindow(by delta: Int) -> Bool {
        guard let repository = loadedRepository, focusReel.shift(by: delta) else { return false }
        saveFocus(for: repository)
        return true
    }

    /// Slides the window while a Focus card is dragged, keeping that card in it.
    @discardableResult
    func shiftFocusWindow(by delta: Int, carrying issueNumber: Int) -> Bool {
        guard let repository = loadedRepository,
              focusReel.shift(by: delta, carrying: issueNumber) else { return false }
        saveFocus(for: repository)
        return true
    }

    @discardableResult
    func revealInFocus(_ issueNumber: Int) -> Bool {
        guard let repository = loadedRepository, focusReel.reveal(issueNumber) else { return false }
        saveFocus(for: repository)
        return true
    }

    func setFocusVisibleCount(_ count: Int) {
        let previous = focusReel
        focusReel.setVisibleCount(count)
        guard focusReel != previous, let repository = loadedRepository else { return }
        saveFocus(for: repository)
    }

    /// `board` picks which clone's Focus board to show. Nil keeps the board
    /// already loaded for this repository, so a revalidation never swaps it.
    func restore(repository: String, board: String? = nil) {
        guard !repository.isEmpty else {
            loadTask?.cancel()
            issues = []
            focusReel = FocusReel(visibleCount: SettingsKey.configuredFocusVisibleCount())
            openIssueNumbers = []
            closedIssueNumbers = []
            loadedRepository = nil
            loadedBoard = nil
            hasSnapshot = false
            return
        }
        let board = board ?? (loadedRepository == repository ? loadedBoard : nil) ?? repository
        if loadedRepository == repository {
            guard loadedBoard != board else { return }
            // Same issues, another clone: only the Focus board changes.
            loadedBoard = board
            focusReel = Self.savedFocusReel(for: board)
            reconcileOrders(with: issues)
            return
        }
        loadTask?.cancel()
        loadTask = nil
        loadTaskRepository = nil
        loadedRepository = repository
        loadedBoard = board
        let snapshot = snapshots[repository]
        issues = snapshot?.issues ?? []
        hasSnapshot = snapshot != nil
        focusReel = Self.savedFocusReel(for: board)
        let savedOrder = Self.savedBacklogOrder[repository]
        openIssueNumbers = savedOrder?.open ?? []
        closedIssueNumbers = savedOrder?.closed ?? []
        if let snapshot {
            reconcileOrders(with: snapshot.issues)
            FocusActivityLog.seedCurrentFocus(repository: repository, issues: allFocused)
        }
        error = nil
    }

    func load(repository: String) async {
        restore(repository: repository)
        await revalidate(repository: repository)
    }

    /// Consumes commands written by `runway-issue` while this board is mounted.
    /// The short poll keeps the command channel independent of terminal focus.
    func processIssueCommands(repository: String) async {
        while !Task.isCancelled {
            processPendingIssueCommands(repository: repository)
            do {
                try await Task.sleep(nanoseconds: 150_000_000)
            } catch {
                return
            }
        }
    }

    private func processPendingIssueCommands(repository: String) {
        let directory = AgentControl.issueCommandDir
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ) else { return }

        for file in files where file.pathExtension == "json" {
            let processing = file.deletingPathExtension().appendingPathExtension("processing")
            guard (try? FileManager.default.moveItem(at: file, to: processing)) != nil else {
                continue
            }
            defer { try? FileManager.default.removeItem(at: processing) }
            guard let data = try? Data(contentsOf: processing),
                  let command = try? JSONDecoder().decode(IssueBoardCommand.self, from: data) else {
                continue
            }

            let first = respond(to: command, repository: repository)
            guard first.retryAfterRefresh else {
                writeIssueBoardResponse(first.response, id: command.id)
                continue
            }
            // A clone or an issue Runway has not seen yet, usually one made
            // seconds ago. Look again on disk and on GitHub before refusing.
            Task { @MainActor [weak self] in
                guard let self else { return }
                await refreshBeforeRetry(command, repository: repository)
                writeIssueBoardResponse(respond(to: command, repository: repository).response, id: command.id)
            }
        }
    }

    private func respond(
        to command: IssueBoardCommand,
        repository: String
    ) -> (response: IssueBoardResponse, retryAfterRefresh: Bool) {
        let targetRepository = command.repository.isEmpty ? repository : command.repository
        let requestedClone = command.clone.flatMap { $0.isEmpty ? nil : $0 }
        let onScreenClone = currentClone(of: repository)
        let isOnScreen = targetRepository == repository
            && (requestedClone == nil || onScreenClone == nil
                || requestedClone?.caseInsensitiveCompare(onScreenClone ?? "") == .orderedSame)
        if !isOnScreen {
            return offScreenResponse(
                to: command,
                repository: targetRepository,
                clone: requestedClone
            )
        }
        if command.action == "list" {
            return (issueBoardResponse(success: true, error: nil), false)
        }
        guard command.action == "move",
              let issueNumber = command.issueNumber,
              let destination = command.destination else {
            return (issueBoardResponse(success: false, error: "Invalid issue board command."), false)
        }
        guard issues.contains(where: { $0.number == issueNumber }),
              let source = lane(of: issueNumber) else {
            return (issueBoardResponse(
                success: false,
                error: "Runway has no issue \(GitHubNumber.reference(issueNumber)) assigned to you in \(targetRepository). Is it assigned to you?"
            ), true)
        }
        let accepted = move(
            issueNumber: issueNumber,
            from: source,
            to: destination,
            before: command.beforeNumber
        )
        return (issueBoardResponse(
            success: accepted,
            error: accepted ? nil : "Runway could not move issue \(GitHubNumber.reference(issueNumber)). \(Self.focusFullHint) Or the issue may not be in the requested lane."
        ), false)
    }

    /// Rescans the clones on disk and refetches the target repository's
    /// issues, so a command for something new gets one more try.
    private func refreshBeforeRetry(_ command: IssueBoardCommand, repository: String) async {
        let target = command.repository.isEmpty ? repository : command.repository
        await GitHubFeed.shared.rescanRepositories()
        if target == loadedRepository {
            await revalidate(repository: target)
        } else {
            await fetchOffScreenIssues(for: target)
        }
    }

    /// Fills the cache for a repository whose board is not on screen, so its
    /// issues are known without opening it first.
    private func fetchOffScreenIssues(for repository: String) async {
        let data = await GH.query([
            "issue", "list",
            "--repo", repository,
            "--assignee", "@me",
            "--state", "all",
            "--limit", "1000",
            "--json", "number,title,state,closedAt,createdAt,updatedAt,url",
        ], cacheFor: 0)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let data,
              let fetched = try? decoder.decode([AssignedIssue].self, from: data),
              repository != loadedRepository else { return }
        let now = Date()
        snapshots[repository] = CachedRepository(
            issues: fetched,
            fetchedAt: now,
            lastFullFetchedAt: now,
            orderedThrough: snapshots[repository]?.orderedThrough
        )
        writeSnapshots()
    }

    /// A command for a board that is not on screen: another repository, or
    /// another clone of this one. It works on that board's saved Focus reel
    /// and the repository's cached issues, leaving the screen as it is.
    private func offScreenResponse(
        to command: IssueBoardCommand,
        repository: String,
        clone: String?
    ) -> (response: IssueBoardResponse, retryAfterRefresh: Bool) {
        let checkouts = GitHubFeed.shared.checkouts(for: repository)
        let checkoutPath: String?
        if let clone {
            guard let match = checkouts.first(where: {
                CloneName.name(ofCheckout: $0).caseInsensitiveCompare(clone) == .orderedSame
            }) else {
                return (boardResponse(
                    success: false,
                    error: "Runway found no clone named \(clone) of \(repository) on this Mac. Pass --clone with the clone's folder name, or check Settings → Clone search covers it.",
                    issues: [],
                    reel: FocusReel(issues: []),
                    clone: clone
                ), true)
            }
            checkoutPath = match
        } else {
            checkoutPath = checkouts.first
        }
        // The preferred clone's board is keyed by the bare repository.
        let checkout = checkoutPath == checkouts.first ? nil : checkoutPath
        let board = FocusBoard.key(repository, checkout: checkout)
        let cloneName = checkoutPath.map(CloneName.name(ofCheckout:)) ?? clone
        let boardIssues = repository == loadedRepository
            ? issues
            : snapshots[repository]?.issues ?? []
        guard !boardIssues.isEmpty else {
            return (boardResponse(
                success: false,
                error: "Runway found no issues assigned to you in \(repository).",
                issues: [],
                reel: FocusReel(issues: []),
                clone: cloneName
            ), true)
        }
        var reel = Self.savedFocusReel(for: board)

        if command.action == "list" {
            // A board never opened keeps whatever it cached last; refetch a
            // stale one so an issue filed a minute ago is listed.
            let isStale = repository != loadedRepository
                && Date().timeIntervalSince(snapshots[repository]?.fetchedAt ?? .distantPast) > 60
            return (
                boardResponse(success: true, error: nil, issues: boardIssues, reel: reel, clone: cloneName),
                isStale
            )
        }
        guard command.action == "move",
              let issueNumber = command.issueNumber,
              let destination = command.destination else {
            return (boardResponse(
                success: false,
                error: "Invalid issue board command.",
                issues: boardIssues,
                reel: reel,
                clone: cloneName
            ), false)
        }
        guard let issue = boardIssues.first(where: { $0.number == issueNumber }) else {
            return (boardResponse(
                success: false,
                error: "Runway has no issue \(GitHubNumber.reference(issueNumber)) assigned to you in \(repository). Is it assigned to you?",
                issues: boardIssues,
                reel: reel,
                clone: cloneName
            ), true)
        }

        let wasFocused = reel.contains(issueNumber)
        let backlog: AssignedIssueLane = issue.isClosed ? .closed : .open
        var order = reel.issues
        switch (wasFocused, destination) {
        case (false, .focus):
            guard FocusReel.canAdd(count: reel.count, limit: SettingsKey.configuredFocusLimit()) else {
                return (boardResponse(
                    success: false,
                    error: "Runway could not move issue \(GitHubNumber.reference(issueNumber)). \(Self.focusFullHint)",
                    issues: boardIssues,
                    reel: reel,
                    clone: cloneName
                ), false)
            }
            insert(issueNumber, before: command.beforeNumber, in: &order)
            FocusActivityLog.record(action: .enteredFocus, repository: repository, issue: issue, from: backlog, to: .focus)
        case (true, .focus):
            if let target = command.beforeNumber { move(issueNumber, before: target, in: &order) }
        case (true, .open), (true, .closed):
            order.removeAll { $0 == issueNumber }
            FocusActivityLog.record(action: .exitedFocus, repository: repository, issue: issue, from: .focus, to: destination)
        case (false, .open), (false, .closed):
            break
        }
        if order != reel.issues {
            reel.replace(with: order)
            var saved = Self.savedFocusReels
            saved[board] = reel
            if let data = try? JSONEncoder().encode(saved) {
                UserDefaults.standard.set(data, forKey: Self.focusReelKey)
            }
            onOffScreenFocusChange?(OffScreenFocusChange(
                repository: repository,
                checkout: checkout,
                issues: reel.issues.compactMap { number in boardIssues.first { $0.number == number } }
            ))
        }
        if destination != .focus, (destination == .closed) != issue.isClosed {
            setStateOffScreen(issueNumber: issueNumber, close: destination == .closed, repository: repository)
        }
        return (boardResponse(success: true, error: nil, issues: boardIssues, reel: reel, clone: cloneName), false)
    }

    /// Close or reopen on GitHub for an off-screen move. The issue lists catch
    /// up on their next refresh; only this repository's own list, when it is
    /// the one loaded, is updated right away.
    private func setStateOffScreen(issueNumber: Int, close: Bool, repository: String) {
        if repository == loadedRepository,
           let index = issues.firstIndex(where: { $0.number == issueNumber }) {
            issues[index].state = close ? "CLOSED" : "OPEN"
            issues[index].closedAt = close ? Date() : nil
            reconcileOrders(with: issues)
            saveSnapshot(for: repository)
        }
        Task { @MainActor [weak self] in
            let result = await GH.run([
                "issue", close ? "close" : "reopen", String(issueNumber), "--repo", repository,
            ])
            guard result == nil else { return }
            self?.error = "GitHub could not \(close ? "close" : "reopen") issue \(GitHubNumber.reference(issueNumber))."
        }
    }

    private func boardResponse(
        success: Bool,
        error: String?,
        issues boardIssues: [AssignedIssue],
        reel: FocusReel,
        clone: String?
    ) -> IssueBoardResponse {
        let focused = reel.allSet
        let byNumber = Dictionary(boardIssues.map { ($0.number, $0) }, uniquingKeysWith: { first, _ in first })
        return IssueBoardResponse(
            success: success,
            error: error,
            clone: clone,
            open: boardIssues.filter { !$0.isClosed && !focused.contains($0.number) },
            focus: reel.issues.compactMap { byNumber[$0] },
            closed: boardIssues.filter { $0.isClosed && !focused.contains($0.number) }
        )
    }

    private func lane(of issueNumber: Int) -> AssignedIssueLane? {
        if focusReel.contains(issueNumber) { return .focus }
        if openIssueNumbers.contains(issueNumber) { return .open }
        if closedIssueNumbers.contains(issueNumber) { return .closed }
        return nil
    }

    /// The folder name of the clone whose Focus board is loaded.
    private func currentClone(of repository: String) -> String? {
        let board = loadedBoard ?? repository
        let path = board.split(separator: "@", maxSplits: 1).dropFirst().first.map(String.init)
            ?? GitHubFeed.shared.checkouts(for: repository).first
            ?? GitHubFeed.shared.localPath(for: repository)
        return path.map(CloneName.name(ofCheckout:))
    }

    private func issueBoardResponse(success: Bool, error: String?) -> IssueBoardResponse {
        IssueBoardResponse(
            success: success,
            error: error,
            clone: loadedRepository.flatMap(currentClone(of:)),
            open: open,
            focus: allFocused,
            closed: closed
        )
    }

    private func writeIssueBoardResponse(_ response: IssueBoardResponse, id: String) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(response) else { return }
        let responseFile = AgentControl.issueResponseDir.appendingPathComponent("\(id).json")
        try? data.write(to: responseFile, options: .atomic)
    }

    func revalidate(repository: String, minimumAge: TimeInterval = 0) async {
        restore(repository: repository)
        guard !repository.isEmpty, loadedRepository == repository else { return }
        if minimumAge > 0,
           let fetchedAt = snapshots[repository]?.fetchedAt,
           Date().timeIntervalSince(fetchedAt) < minimumAge {
            return
        }
        if let loadTask, loadTaskRepository == repository {
            let previousFullFetch = snapshots[repository]?.lastFullFetchedAt
            await loadTask.value
            if minimumAge > 0 || snapshots[repository]?.lastFullFetchedAt != previousFullFetch {
                return
            }
        }

        loading = true
        error = nil

        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            let previousSnapshot = snapshots[repository]
            let now = Date()
            let needsFullRefresh = Self.needsFullRefresh(
                lastFullFetchedAt: previousSnapshot?.lastFullFetchedAt,
                now: now,
                explicitlyRequested: minimumAge == 0
            )
            var arguments = [
                "issue", "list",
                "--repo", repository,
                "--assignee", "@me",
                "--state", "all",
                "--limit", "1000",
                "--json", "number,title,state,closedAt,createdAt,updatedAt,url",
            ]
            if !needsFullRefresh, let fetchedAt = previousSnapshot?.fetchedAt {
                arguments.append(contentsOf: [
                    "--search",
                    "updated:>=\(Self.iso8601.string(from: fetchedAt.addingTimeInterval(-300)))",
                ])
            }
            // A full assigned-issue list is the only response that can prove an
            // issue disappeared after unassignment. Do not reuse a cached full
            // response when the user explicitly refreshes the board.
            let data = await GH.query(arguments, cacheFor: needsFullRefresh ? 0 : 20)
            guard !Task.isCancelled, loadedRepository == repository else { return }
            guard let data else {
                error = GitHubFeed.ghHint
                loading = false
                return
            }
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            guard let decoded = try? decoder.decode([AssignedIssue].self, from: data) else {
                error = "Runway could not read the assigned issues returned by GitHub."
                loading = false
                return
            }
            let reconciledRenames = Self.preservingOptimisticTitles(
                in: decoded,
                pending: pendingRenameTitles[repository] ?? [:]
            )
            let fetched = reconciledRenames.issues
            for issueNumber in reconciledRenames.confirmed {
                pendingRenameTitles[repository]?[issueNumber] = nil
            }
            if pendingRenameTitles[repository]?.isEmpty == true {
                pendingRenameTitles[repository] = nil
            }
            let previousNumbers = Set(previousSnapshot?.issues.map(\.number) ?? [])
            let orderingCutoff = previousSnapshot?.orderedThrough
                ?? previousSnapshot?.lastFullFetchedAt
                ?? previousSnapshot?.fetchedAt
                ?? .distantPast
            let newlyDiscovered = Set(fetched.compactMap { issue -> Int? in
                if !previousNumbers.contains(issue.number) { return issue.number }
                if let createdAt = issue.createdAt, createdAt > orderingCutoff {
                    return issue.number
                }
                return nil
            })
            if needsFullRefresh {
                let fetchedNumbers = Set(fetched.map(\.number))
                for issueNumber in focusReel.issues where !fetchedNumbers.contains(issueNumber) {
                    guard let issue = issues.first(where: { $0.number == issueNumber }) else { continue }
                    FocusActivityLog.record(
                        action: .exitedFocus,
                        repository: repository,
                        issue: issue,
                        from: .focus,
                        to: issue.isClosed ? .closed : .open,
                        cause: "revalidation"
                    )
                }
            }
            issues = Self.issuesAfterRefresh(
                current: issues, fetched: fetched, fullRefresh: needsFullRefresh
            )
            hasSnapshot = true
            reconcileOrders(with: issues, prioritizing: newlyDiscovered)
            FocusActivityLog.seedCurrentFocus(repository: repository, issues: allFocused)
            saveSnapshot(
                for: repository,
                fetchedAt: now,
                lastFullFetchedAt: needsFullRefresh
                    ? now
                    : previousSnapshot?.lastFullFetchedAt,
                orderedThrough: now
            )
            saveFocus(for: repository)
            saveBacklogOrder(for: repository)
            loading = false
        }
        loadTask = task
        loadTaskRepository = repository
        await task.value
        if loadTaskRepository == repository {
            loadTask = nil
            loadTaskRepository = nil
        }
    }

    static func needsFullRefresh(
        lastFullFetchedAt: Date?,
        now: Date,
        explicitlyRequested: Bool
    ) -> Bool {
        guard !explicitlyRequested, let lastFullFetchedAt else { return true }
        return now.timeIntervalSince(lastFullFetchedAt) >= 60
    }

    static func issuesAfterRefresh(
        current: [AssignedIssue],
        fetched: [AssignedIssue],
        fullRefresh: Bool
    ) -> [AssignedIssue] {
        if fullRefresh { return fetched }
        var merged = Dictionary(uniqueKeysWithValues: current.map { ($0.number, $0) })
        for issue in fetched { merged[issue.number] = issue }
        return merged.values.sorted {
            ($0.updatedAt ?? .distantPast) > ($1.updatedAt ?? .distantPast)
        }
    }

    private func reconcileOrders(
        with availableIssues: [AssignedIssue],
        prioritizing issueNumbers: Set<Int> = []
    ) {
        let defaultOpen = availableIssues
            .filter { !$0.isClosed }
            .sorted { $0.number > $1.number }
            .map(\.number)
        let defaultClosed = availableIssues
            .filter(\.isClosed)
            .sorted { ($0.closedAt ?? .distantPast) > ($1.closedAt ?? .distantPast) }
            .map(\.number)
        openIssueNumbers = Self.mergedOrder(
            openIssueNumbers,
            available: defaultOpen,
            prioritizing: issueNumbers
        )
        closedIssueNumbers = Self.mergedOrder(
            closedIssueNumbers,
            available: defaultClosed,
            prioritizing: issueNumbers
        )
        focusReel.reconcile(available: Set(availableIssues.map(\.number)))
    }

    static func resetSavedBacklogOrder() {
        UserDefaults.standard.removeObject(forKey: backlogOrderKey)
        NotificationCenter.default.post(name: .assignedIssueBacklogOrderReset, object: nil)
    }

    func resetBacklogOrder() {
        guard let repository = loadedRepository else { return }
        openIssueNumbers = issues
            .filter { !$0.isClosed }
            .sorted { $0.number > $1.number }
            .map(\.number)
        closedIssueNumbers = issues
            .filter(\.isClosed)
            .sorted { ($0.closedAt ?? .distantPast) > ($1.closedAt ?? .distantPast) }
            .map(\.number)
        saveBacklogOrder(for: repository)
    }

    func promoteToFocus(issueNumber: Int) {
        guard let repository = loadedRepository,
              issues.contains(where: { $0.number == issueNumber }),
              !focusReel.contains(issueNumber),
              canAddToFocus else { return }
        focusReel.replace(with: focusReel.issues + [issueNumber])
        focusReel.reveal(issueNumber)
        saveFocus(for: repository)
        if let issue = issues.first(where: { $0.number == issueNumber }) {
            FocusActivityLog.record(
                action: .enteredFocus,
                repository: repository,
                issue: issue,
                from: issue.isClosed ? .closed : .open,
                to: .focus
            )
        }
    }

    func removeFromFocus(issueNumber: Int) {
        guard let repository = loadedRepository,
              let issue = issues.first(where: { $0.number == issueNumber }),
              focusReel.contains(issueNumber) else { return }
        focusReel.replace(with: focusReel.issues.filter { $0 != issueNumber })
        saveFocus(for: repository)
        FocusActivityLog.record(
            action: .exitedFocus,
            repository: repository,
            issue: issue,
            from: .focus,
            to: issue.isClosed ? .closed : .open
        )
    }

    func moveFocused(issueNumber: Int, toTarget targetNumber: Int) {
        _ = move(
            issueNumber: issueNumber,
            from: .focus,
            to: .focus,
            before: targetNumber
        )
    }

    @discardableResult
    func renameIssue(issueNumber: Int, newTitle: String) -> Bool {
        let trimmed = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let repository = loadedRepository,
              let issueIndex = issues.firstIndex(where: { $0.number == issueNumber }),
              !trimmed.isEmpty,
              issues[issueIndex].title != trimmed else { return false }

        let previous = issues[issueIndex]
        issues[issueIndex].title = trimmed
        pendingRenameTitles[repository, default: [:]][issueNumber] = trimmed
        saveSnapshot(for: repository)
        mutateGitHubTitle(
            issueNumber: issueNumber,
            title: trimmed,
            repository: repository,
            rollback: previous
        )
        return true
    }

    /// A cached issue-list response can briefly trail a successful edit. Keep
    /// the optimistic title until GitHub itself returns it, then retire the pin.
    static func preservingOptimisticTitles(
        in fetched: [AssignedIssue],
        pending: [Int: String]
    ) -> (issues: [AssignedIssue], confirmed: Set<Int>) {
        var confirmed = Set<Int>()
        let issues = fetched.map { issue -> AssignedIssue in
            guard let optimisticTitle = pending[issue.number] else { return issue }
            if issue.title == optimisticTitle {
                confirmed.insert(issue.number)
                return issue
            }
            var preserved = issue
            preserved.title = optimisticTitle
            return preserved
        }
        return (issues, confirmed)
    }

    @discardableResult
    func setClosed(issueNumber: Int, closed: Bool) -> Bool {
        guard let repository = loadedRepository,
              let issueIndex = issues.firstIndex(where: { $0.number == issueNumber }),
              issues[issueIndex].isClosed != closed else { return false }

        let issue = issues[issueIndex]
        let rollback = IssueMoveRollback(
            issue: issue,
            focusIndex: focusReel.issues.firstIndex(of: issueNumber),
            openIndex: openIssueNumbers.firstIndex(of: issueNumber),
            closedIndex: closedIssueNumbers.firstIndex(of: issueNumber),
            attemptedDestination: closed ? .closed : .open,
            shouldLogFocusReturn: false
        )

        let reordered = Self.ordersAfterStateChange(
            open: openIssueNumbers,
            closed: closedIssueNumbers,
            issueNumber: issueNumber,
            closed: closed
        )
        openIssueNumbers = reordered.open
        closedIssueNumbers = reordered.closed
        issues[issueIndex].state = closed ? "CLOSED" : "OPEN"
        issues[issueIndex].closedAt = closed ? Date() : nil
        saveSnapshot(for: repository)
        saveBacklogOrder(for: repository)
        mutateGitHubState(
            issueNumber: issueNumber,
            close: closed,
            repository: repository,
            rollback: rollback
        )
        return true
    }

    @discardableResult
    func move(
        issueNumber: Int,
        from source: AssignedIssueLane,
        to destination: AssignedIssueLane,
        before targetNumber: Int?,
        savesOrder: Bool = true
    ) -> Bool {
        guard let repository = loadedRepository,
              let issue = issues.first(where: { $0.number == issueNumber }) else { return false }

        if source == destination {
            guard let targetNumber, issueNumber != targetNumber else { return true }
            switch destination {
            case .focus:
                guard focusReel.contains(issueNumber) else { return false }
                var order = focusReel.issues
                move(issueNumber, before: targetNumber, in: &order)
                focusReel.replace(with: order)
            case .open:
                move(issueNumber, before: targetNumber, in: &openIssueNumbers)
            case .closed:
                move(issueNumber, before: targetNumber, in: &closedIssueNumbers)
            }
            if savesOrder { saveOrder() }
            return true
        }

        switch (source, destination) {
        case (.open, .focus), (.closed, .focus):
            guard !focusReel.contains(issueNumber), canAddToFocus else { return false }
            var order = focusReel.issues
            insert(issueNumber, before: targetNumber, in: &order)
            focusReel.replace(with: order)
            focusReel.reveal(issueNumber)
            saveFocus(for: repository)
            FocusActivityLog.record(
                action: .enteredFocus,
                repository: repository,
                issue: issue,
                from: source,
                to: .focus
            )
            return true

        case (.focus, .open), (.focus, .closed):
            guard focusReel.contains(issueNumber) else { return false }
            let shouldClose = destination == .closed
            let needsGitHubMutation = issue.isClosed != shouldClose
            let rollback = IssueMoveRollback(
                issue: issue,
                focusIndex: focusReel.issues.firstIndex(of: issueNumber),
                openIndex: openIssueNumbers.firstIndex(of: issueNumber),
                closedIndex: closedIssueNumbers.firstIndex(of: issueNumber),
                attemptedDestination: destination,
                shouldLogFocusReturn: true
            )

            focusReel.replace(with: focusReel.issues.filter { $0 != issueNumber })
            if destination == .open {
                closedIssueNumbers.removeAll { $0 == issueNumber }
                openIssueNumbers = Self.returnedBacklogOrder(
                    openIssueNumbers,
                    issueNumber: issueNumber,
                    before: targetNumber
                )
            } else {
                openIssueNumbers.removeAll { $0 == issueNumber }
                closedIssueNumbers = Self.returnedBacklogOrder(
                    closedIssueNumbers,
                    issueNumber: issueNumber,
                    before: targetNumber
                )
            }
            if needsGitHubMutation,
               let issueIndex = issues.firstIndex(where: { $0.number == issueNumber }) {
                issues[issueIndex].state = shouldClose ? "CLOSED" : "OPEN"
                issues[issueIndex].closedAt = shouldClose ? Date() : nil
                saveSnapshot(for: repository)
            }
            saveFocus(for: repository)
            saveBacklogOrder(for: repository)
            FocusActivityLog.record(
                action: .exitedFocus,
                repository: repository,
                issue: issue,
                from: .focus,
                to: destination
            )

            if needsGitHubMutation {
                mutateGitHubState(
                    issueNumber: issueNumber,
                    close: shouldClose,
                    repository: repository,
                    rollback: rollback
                )
            }
            return true

        default:
            return false
        }
    }

    /// One lookup table per call: the lanes rebuild on every render, and a
    /// linear search per number made that quadratic on a board of 500 issues.
    private func orderedIssues(_ order: [Int]) -> [AssignedIssue] {
        let byNumber = Dictionary(issues.map { ($0.number, $0) }, uniquingKeysWith: { first, _ in first })
        return order.compactMap { byNumber[$0] }
    }

    private func move(_ issueNumber: Int, before targetNumber: Int, in order: inout [Int]) {
        guard issueNumber != targetNumber,
              order.contains(issueNumber),
              let targetIndex = order.firstIndex(of: targetNumber) else { return }
        order.removeAll { $0 == issueNumber }
        order.insert(issueNumber, at: min(targetIndex, order.endIndex))
    }

    private func insert(_ issueNumber: Int, before targetNumber: Int?, in order: inout [Int]) {
        order.removeAll { $0 == issueNumber }
        guard let targetNumber, let targetIndex = order.firstIndex(of: targetNumber) else {
            order.append(issueNumber)
            return
        }
        order.insert(issueNumber, at: targetIndex)
    }

    static func returnedBacklogOrder(
        _ order: [Int],
        issueNumber: Int,
        before targetNumber: Int?
    ) -> [Int] {
        guard let targetNumber else {
            if order.contains(issueNumber) { return order }
            return [issueNumber] + order
        }

        var reordered = order
        reordered.removeAll { $0 == issueNumber }
        guard let targetIndex = reordered.firstIndex(of: targetNumber) else {
            if order.contains(issueNumber) { return order }
            return [issueNumber] + order
        }
        reordered.insert(issueNumber, at: targetIndex)
        return reordered
    }

    static func ordersAfterStateChange(
        open: [Int],
        closed: [Int],
        issueNumber: Int,
        closed shouldClose: Bool
    ) -> (open: [Int], closed: [Int]) {
        var nextOpen = open.filter { $0 != issueNumber }
        var nextClosed = closed.filter { $0 != issueNumber }
        if shouldClose {
            nextClosed.insert(issueNumber, at: 0)
        } else {
            nextOpen.insert(issueNumber, at: 0)
        }
        return (nextOpen, nextClosed)
    }

    private func mutateGitHubTitle(
        issueNumber: Int,
        title: String,
        repository: String,
        rollback: AssignedIssue
    ) {
        error = nil
        Task { @MainActor [weak self] in
            let result = await GH.run([
                "issue",
                "edit",
                String(issueNumber),
                "--repo",
                repository,
                "--title",
                title,
            ])
            guard let self, loadedRepository == repository else { return }
            guard result == nil else { return }
            guard pendingRenameTitles[repository]?[issueNumber] == title else { return }
            pendingRenameTitles[repository]?[issueNumber] = nil
            if pendingRenameTitles[repository]?.isEmpty == true {
                pendingRenameTitles[repository] = nil
            }
            guard let issueIndex = issues.firstIndex(where: { $0.number == issueNumber }) else { return }
            issues[issueIndex] = rollback
            saveSnapshot(for: repository)
            error = "GitHub could not rename issue \(GitHubNumber.reference(issueNumber))."
        }
    }

    private func mutateGitHubState(
        issueNumber: Int,
        close: Bool,
        repository: String,
        rollback: IssueMoveRollback
    ) {
        error = nil
        Task { @MainActor [weak self] in
            let result = await GH.run([
                "issue",
                close ? "close" : "reopen",
                String(issueNumber),
                "--repo",
                repository,
            ])
            guard let self,
                  loadedRepository == repository,
                  result == nil else { return }
            rollbackIssueMove(issueNumber: issueNumber, using: rollback)
            error = "GitHub could not \(close ? "close" : "reopen") issue \(GitHubNumber.reference(issueNumber)). The move was undone."
        }
    }

    private func rollbackIssueMove(
        issueNumber: Int,
        using rollback: IssueMoveRollback
    ) {
        guard let issueIndex = issues.firstIndex(where: { $0.number == issueNumber }) else { return }
        issues[issueIndex] = rollback.issue
        openIssueNumbers.removeAll { $0 == issueNumber }
        closedIssueNumbers.removeAll { $0 == issueNumber }
        var focusOrder = focusReel.issues.filter { $0 != issueNumber }
        restore(issueNumber, at: rollback.focusIndex, in: &focusOrder)
        focusReel.replace(with: focusOrder)
        restore(issueNumber, at: rollback.openIndex, in: &openIssueNumbers)
        restore(issueNumber, at: rollback.closedIndex, in: &closedIssueNumbers)
        if let repository = loadedRepository {
            saveSnapshot(for: repository)
            saveFocus(for: repository)
            saveBacklogOrder(for: repository)
            if rollback.focusIndex != nil, rollback.shouldLogFocusReturn {
                FocusActivityLog.record(
                    action: .enteredFocus,
                    repository: repository,
                    issue: rollback.issue,
                    from: rollback.attemptedDestination,
                    to: .focus,
                    cause: "github_rollback"
                )
            }
        }
    }

    private func restore(_ issueNumber: Int, at index: Int?, in order: inout [Int]) {
        guard let index else { return }
        order.insert(issueNumber, at: min(index, order.endIndex))
    }

    /// Writes the lane orders a drag changed in memory. Saving on every step
    /// of a drag rewrote the stored orders of every repository each time a
    /// card passed another, and every settings-backed view re-rendered with it.
    func saveOrder() {
        guard let repository = loadedRepository else { return }
        saveFocus(for: repository)
        saveBacklogOrder(for: repository)
    }

    private func saveFocus(for repository: String) {
        guard repository == loadedRepository else { return }
        var saved = Self.savedFocusReels
        saved[loadedBoard ?? repository] = focusReel
        guard let data = try? JSONEncoder().encode(saved) else { return }
        UserDefaults.standard.set(data, forKey: Self.focusReelKey)
    }

    private func saveBacklogOrder(for repository: String) {
        var saved = Self.savedBacklogOrder
        saved[repository] = SavedBacklogOrder(
            open: openIssueNumbers,
            closed: closedIssueNumbers
        )
        guard let data = try? JSONEncoder().encode(saved) else { return }
        UserDefaults.standard.set(data, forKey: Self.backlogOrderKey)
    }

    private func saveSnapshot(
        for repository: String,
        fetchedAt: Date? = nil,
        lastFullFetchedAt: Date? = nil,
        orderedThrough: Date? = nil
    ) {
        let validationDate = fetchedAt
            ?? snapshots[repository]?.fetchedAt
            ?? .distantPast
        snapshots[repository] = CachedRepository(
            issues: issues,
            fetchedAt: validationDate,
            lastFullFetchedAt: lastFullFetchedAt
                ?? snapshots[repository]?.lastFullFetchedAt,
            orderedThrough: orderedThrough
                ?? snapshots[repository]?.orderedThrough
        )
        writeSnapshots()
    }

    private func writeSnapshots() {
        guard let data = try? JSONEncoder().encode(snapshots) else { return }
        try? FileManager.default.createDirectory(
            at: AgentControl.supportDir,
            withIntermediateDirectories: true
        )
        try? data.write(to: Self.snapshotFile, options: .atomic)
    }

    private static var savedFocus: [String: [Int]] {
        guard let data = UserDefaults.standard.data(forKey: focusedIssuesKey),
              let saved = try? JSONDecoder().decode([String: [Int]].self, from: data) else {
            return [:]
        }
        return saved
    }

    private static var savedFocusReels: [String: FocusReel] {
        decodedFocus(forKey: focusReelKey)
    }

    private static func decodedFocus(forKey key: String) -> [String: FocusReel] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let saved = try? JSONDecoder().decode([String: FocusReel].self, from: data) else {
            return [:]
        }
        return saved
    }

    /// The reel for a repository, migrating older formats on first read: the
    /// paginated boards flatten in board order, and the single list before them
    /// becomes the whole reel. Older keys stay untouched.
    static func savedFocusReel(
        for repository: String,
        visibleCount: Int = SettingsKey.configuredFocusVisibleCount()
    ) -> FocusReel {
        var reel = savedFocusReels[repository]
            ?? decodedFocus(forKey: legacyFocusBoardsKey)[repository]
            ?? FocusReel(issues: savedFocus[repository] ?? [])
        reel.setVisibleCount(visibleCount)
        return reel
    }

    static func savedVisibleFocusIssues(for repository: String) -> [Int] {
        savedFocusReel(for: repository).visible
    }

    static func savedFocusIssues(for repository: String) -> [Int] {
        savedFocusReel(for: repository).issues
    }

    /// Shown when Focus refuses another issue.
    static var focusFullHint: String {
        guard let limit = SettingsKey.configuredFocusLimit() else {
            return "The issue may already be in Focus."
        }
        return "Focus may already hold its limit of \(limit) issues (Settings, Agents)."
    }

    private struct SavedBacklogOrder: Codable {
        let open: [Int]
        let closed: [Int]
    }

    private struct IssueMoveRollback {
        let issue: AssignedIssue
        let focusIndex: Int?
        let openIndex: Int?
        let closedIndex: Int?
        let attemptedDestination: AssignedIssueLane
        let shouldLogFocusReturn: Bool
    }

    private struct CachedRepository: Codable {
        let issues: [AssignedIssue]
        let fetchedAt: Date
        let lastFullFetchedAt: Date?
        let orderedThrough: Date?
    }

    private static let iso8601 = ISO8601DateFormatter()

    private static func readSnapshots() -> [String: CachedRepository] {
        guard let data = try? Data(contentsOf: snapshotFile),
              let snapshots = try? JSONDecoder().decode(
                [String: CachedRepository].self,
                from: data
              ) else { return [:] }
        return snapshots
    }

    private static var savedBacklogOrder: [String: SavedBacklogOrder] {
        guard let data = UserDefaults.standard.data(forKey: backlogOrderKey),
              let saved = try? JSONDecoder().decode(
                [String: SavedBacklogOrder].self,
                from: data
              ) else {
            return [:]
        }
        return saved
    }

    private static func mergedOrder(
        _ saved: [Int],
        available: [Int],
        prioritizing issueNumbers: Set<Int>
    ) -> [Int] {
        let availableSet = Set(available)
        let prioritized = available.filter(issueNumbers.contains)
        let prioritizedSet = Set(prioritized)
        let retained = saved.filter {
            availableSet.contains($0) && !prioritizedSet.contains($0)
        }
        let retainedSet = Set(retained)
        let additions = available.filter {
            !prioritizedSet.contains($0) && !retainedSet.contains($0)
        }
        return prioritized + additions + retained
    }
}
