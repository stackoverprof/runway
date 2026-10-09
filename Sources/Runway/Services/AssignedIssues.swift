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
    let issueNumber: Int?
    let destination: AssignedIssueLane?
    let beforeNumber: Int?
    let lane: AssignedIssueLane?
}

private struct IssueBoardResponse: Codable {
    let success: Bool
    let error: String?
    let open: [AssignedIssue]
    let focus: [AssignedIssue]
    let closed: [AssignedIssue]
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
    private(set) var focusBoards = FocusBoards()
    private(set) var openIssueNumbers: [Int] = []
    private(set) var closedIssueNumbers: [Int] = []

    private var loadedRepository: String?
    private var loadTask: Task<Void, Never>?
    private var loadTaskRepository: String?
    @ObservationIgnored private var snapshots = AssignedIssues.readSnapshots()
    @ObservationIgnored private var pendingRenameTitles: [String: [Int: String]] = [:]
    private static let focusedIssuesKey = "runway.focusedAssignedIssueNumbers.v2"
    private static let focusBoardsKey = "runway.focusBoards.v1"
    private static let backlogOrderKey = "runway.assignedIssueBacklogOrder.v2"
    private static var snapshotFile: URL {
        AgentControl.supportDir.appendingPathComponent("assigned-issues-cache.json")
    }

    var open: [AssignedIssue] {
        let focused = focusBoards.allSet
        return orderedIssues(openIssueNumbers)
            .filter { !$0.isClosed && !focused.contains($0.number) }
    }

    var closed: [AssignedIssue] {
        let focused = focusBoards.allSet
        return orderedIssues(closedIssueNumbers)
            .filter { $0.isClosed && !focused.contains($0.number) }
    }

    var focusedIssueNumbers: [Int] { focusBoards.selected }
    var activeFocusBoardIndex: Int { focusBoards.selectedIndex }
    var focusBoardCount: Int { focusBoards.count }
    var allFocused: [AssignedIssue] { orderedIssues(focusBoards.all) }

    var focused: [AssignedIssue] {
        orderedIssues(focusedIssueNumbers)
    }

    func boardIndex(containing issueNumber: Int) -> Int? {
        focusBoards.boardIndex(containing: issueNumber)
    }

    func selectFocusBoard(_ index: Int) {
        guard let repository = loadedRepository, focusBoards.selectedIndex != index,
              (0..<focusBoards.count).contains(index) else { return }
        focusBoards.select(index)
        saveFocus(for: repository)
    }

    func createFocusBoard() {
        guard let repository = loadedRepository else { return }
        focusBoards.create()
        saveFocus(for: repository)
    }

    /// Deleting a board returns its issues to Open or Closed, the same as
    /// taking each one out of Focus. Their lanes already hold them, so only
    /// the board membership changes; the log records each exit.
    func deleteFocusBoard(_ index: Int) {
        guard let repository = loadedRepository,
              let removed = focusBoards.remove(at: index) else { return }
        saveFocus(for: repository)
        for issueNumber in removed {
            guard let issue = issues.first(where: { $0.number == issueNumber }) else { continue }
            FocusActivityLog.record(
                action: .exitedFocus,
                repository: repository,
                issue: issue,
                from: .focus,
                to: issue.isClosed ? .closed : .open,
                cause: "board_deleted"
            )
        }
    }

    func restore(repository: String) {
        guard !repository.isEmpty else {
            loadTask?.cancel()
            issues = []
            focusBoards = FocusBoards()
            openIssueNumbers = []
            closedIssueNumbers = []
            loadedRepository = nil
            hasSnapshot = false
            return
        }
        guard loadedRepository != repository else { return }
        loadTask?.cancel()
        loadTask = nil
        loadTaskRepository = nil
        loadedRepository = repository
        let snapshot = snapshots[repository]
        issues = snapshot?.issues ?? []
        hasSnapshot = snapshot != nil
        focusBoards = Self.savedFocusBoards[repository]
            ?? FocusBoards(boards: [Self.savedFocus[repository] ?? []])
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

            let response: IssueBoardResponse
            if !command.repository.isEmpty, command.repository != repository {
                response = issueBoardResponse(
                    success: false,
                    error: "Runway is currently showing \(repository), not \(command.repository)."
                )
            } else if command.action == "list" {
                response = issueBoardResponse(success: true, error: nil)
            } else if command.action == "move",
                      let issueNumber = command.issueNumber,
                      let destination = command.destination,
                      issues.contains(where: { $0.number == issueNumber }),
                      let source = lane(of: issueNumber) {
                let accepted = move(
                    issueNumber: issueNumber,
                    from: source,
                    to: destination,
                    before: command.beforeNumber
                )
                response = issueBoardResponse(
                    success: accepted,
                    error: accepted ? nil : "Runway could not move issue \(GitHubNumber.reference(issueNumber)). The Focus board may already contain five issues, or the issue may not be in the requested lane."
                )
            } else {
                response = issueBoardResponse(
                    success: false,
                    error: "Invalid issue board command."
                )
            }
            writeIssueBoardResponse(response, id: command.id)
        }
    }

    private func lane(of issueNumber: Int) -> AssignedIssueLane? {
        if focusBoards.allSet.contains(issueNumber) { return .focus }
        if openIssueNumbers.contains(issueNumber) { return .open }
        if closedIssueNumbers.contains(issueNumber) { return .closed }
        return nil
    }

    private func issueBoardResponse(success: Bool, error: String?) -> IssueBoardResponse {
        IssueBoardResponse(
            success: success,
            error: error,
            open: open,
            focus: focused,
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
                for issueNumber in focusBoards.all where !fetchedNumbers.contains(issueNumber) {
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
        focusBoards.reconcile(available: Set(availableIssues.map(\.number)))
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
              !focusBoards.allSet.contains(issueNumber),
              focusedIssueNumbers.count < 5 else { return }
        focusBoards.replaceSelected(with: focusedIssueNumbers + [issueNumber])
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
              focusedIssueNumbers.contains(issueNumber) else { return }
        focusBoards.replaceSelected(with: focusedIssueNumbers.filter { $0 != issueNumber })
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

    func restoreFocusedOrder(_ order: [Int]) {
        guard let repository = loadedRepository else { return }
        let available = Set(focusedIssueNumbers)
        focusBoards.replaceSelected(with: order.filter(available.contains))
        saveFocus(for: repository)
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
            focusIndex: focusedIssueNumbers.firstIndex(of: issueNumber),
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
        before targetNumber: Int?
    ) -> Bool {
        guard let repository = loadedRepository,
              let issue = issues.first(where: { $0.number == issueNumber }) else { return false }

        if source == destination {
            guard let targetNumber, issueNumber != targetNumber else { return true }
            switch destination {
            case .focus:
                guard focusedIssueNumbers.contains(issueNumber) else { return false }
                var order = focusedIssueNumbers
                move(issueNumber, before: targetNumber, in: &order)
                focusBoards.replaceSelected(with: order)
                saveFocus(for: repository)
            case .open:
                move(issueNumber, before: targetNumber, in: &openIssueNumbers)
                saveBacklogOrder(for: repository)
            case .closed:
                move(issueNumber, before: targetNumber, in: &closedIssueNumbers)
                saveBacklogOrder(for: repository)
            }
            return true
        }

        switch (source, destination) {
        case (.open, .focus), (.closed, .focus):
            guard !focusBoards.allSet.contains(issueNumber),
                  focusedIssueNumbers.count < 5 else { return false }
            var order = focusedIssueNumbers
            insert(issueNumber, before: targetNumber, in: &order)
            focusBoards.replaceSelected(with: order)
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
            guard focusedIssueNumbers.contains(issueNumber) else { return false }
            let shouldClose = destination == .closed
            let needsGitHubMutation = issue.isClosed != shouldClose
            let rollback = IssueMoveRollback(
                issue: issue,
                focusIndex: focusedIssueNumbers.firstIndex(of: issueNumber),
                openIndex: openIssueNumbers.firstIndex(of: issueNumber),
                closedIndex: closedIssueNumbers.firstIndex(of: issueNumber),
                attemptedDestination: destination,
                shouldLogFocusReturn: true
            )

            focusBoards.replaceSelected(with: focusedIssueNumbers.filter { $0 != issueNumber })
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

    private func orderedIssues(_ order: [Int]) -> [AssignedIssue] {
        order.compactMap { number in issues.first { $0.number == number } }
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
        focusBoards.replaceSelected(with: focusedIssueNumbers.filter { $0 != issueNumber })
        openIssueNumbers.removeAll { $0 == issueNumber }
        closedIssueNumbers.removeAll { $0 == issueNumber }
        var focusOrder = focusedIssueNumbers
        restore(issueNumber, at: rollback.focusIndex, in: &focusOrder)
        focusBoards.replaceSelected(with: focusOrder)
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

    private func saveFocus(for repository: String) {
        var saved = Self.savedFocusBoards
        saved[repository] = focusBoards
        guard let data = try? JSONEncoder().encode(saved) else { return }
        UserDefaults.standard.set(data, forKey: Self.focusBoardsKey)
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

    private static var savedFocusBoards: [String: FocusBoards] {
        guard let data = UserDefaults.standard.data(forKey: focusBoardsKey),
              let saved = try? JSONDecoder().decode([String: FocusBoards].self, from: data) else {
            return [:]
        }
        return saved
    }

    static func savedSelectedFocusIssues(for repository: String) -> [Int] {
        (savedFocusBoards[repository]
            ?? FocusBoards(boards: [savedFocus[repository] ?? []])).selected
    }

    static func savedSelectedFocusBoardIndex(for repository: String) -> Int {
        savedFocusBoards[repository]?.selectedIndex ?? 0
    }

    static func savedBoardIndex(containing issueNumber: Int, in repository: String) -> Int? {
        (savedFocusBoards[repository]
            ?? FocusBoards(boards: [savedFocus[repository] ?? []]))
            .boardIndex(containing: issueNumber)
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
