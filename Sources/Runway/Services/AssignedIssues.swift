import Foundation

struct AssignedIssue: Codable, Identifiable, Sendable {
    let number: Int
    let title: String
    var state: String
    var closedAt: Date?
    let createdAt: Date?
    let updatedAt: Date?
    let url: URL

    var id: Int { number }
    var isClosed: Bool { state == "CLOSED" }
}

enum AssignedIssueLane: String, Codable, Hashable {
    case focus
    case open
    case closed
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
    private(set) var focusedIssueNumbers: [Int] = []
    private(set) var openIssueNumbers: [Int] = []
    private(set) var closedIssueNumbers: [Int] = []

    private var loadedRepository: String?
    private var loadTask: Task<Void, Never>?
    private var loadTaskRepository: String?
    @ObservationIgnored private var snapshots = AssignedIssues.readSnapshots()
    private static let focusedIssuesKey = "runway.focusedAssignedIssueNumbers.v2"
    private static let backlogOrderKey = "runway.assignedIssueBacklogOrder.v2"
    private static var snapshotFile: URL {
        AgentControl.supportDir.appendingPathComponent("assigned-issues-cache.json")
    }

    var open: [AssignedIssue] {
        orderedIssues(openIssueNumbers)
            .filter { !$0.isClosed && !focusedIssueNumbers.contains($0.number) }
    }

    var closed: [AssignedIssue] {
        orderedIssues(closedIssueNumbers)
            .filter { $0.isClosed && !focusedIssueNumbers.contains($0.number) }
    }

    var focused: [AssignedIssue] {
        focusedIssueNumbers.compactMap { number in
            issues.first { $0.number == number }
        }
    }

    func restore(repository: String) {
        guard !repository.isEmpty else {
            loadTask?.cancel()
            issues = []
            focusedIssueNumbers = []
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
        focusedIssueNumbers = Self.savedFocus[repository] ?? []
        let savedOrder = Self.savedBacklogOrder[repository]
        openIssueNumbers = savedOrder?.open ?? []
        closedIssueNumbers = savedOrder?.closed ?? []
        if let snapshot {
            reconcileOrders(with: snapshot.issues)
            FocusActivityLog.seedCurrentFocus(repository: repository, issues: focused)
        }
        error = nil
    }

    func load(repository: String) async {
        restore(repository: repository)
        await revalidate(repository: repository)
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
            await loadTask.value
            return
        }

        loading = true
        error = nil

        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            let previousSnapshot = snapshots[repository]
            let now = Date()
            let needsFullRefresh = previousSnapshot == nil
                || previousSnapshot?.lastFullFetchedAt == nil
                || now.timeIntervalSince(previousSnapshot?.lastFullFetchedAt ?? .distantPast) > 6 * 3_600
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
            let data = await GH.query(arguments, cacheFor: 20)
            guard !Task.isCancelled, loadedRepository == repository else { return }
            guard let data else {
                error = GitHubFeed.ghHint
                loading = false
                return
            }
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            guard let fetched = try? decoder.decode([AssignedIssue].self, from: data) else {
                error = "Runway could not read the assigned issues returned by GitHub."
                loading = false
                return
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
                for issueNumber in focusedIssueNumbers where !fetchedNumbers.contains(issueNumber) {
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
                issues = fetched
            } else {
                var merged = Dictionary(uniqueKeysWithValues: issues.map { ($0.number, $0) })
                for issue in fetched { merged[issue.number] = issue }
                issues = merged.values.sorted {
                    ($0.updatedAt ?? .distantPast) > ($1.updatedAt ?? .distantPast)
                }
            }
            hasSnapshot = true
            reconcileOrders(with: issues, prioritizing: newlyDiscovered)
            FocusActivityLog.seedCurrentFocus(repository: repository, issues: focused)
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
        focusedIssueNumbers = Array(focusedIssueNumbers.filter { number in
            availableIssues.contains { $0.number == number }
        }.prefix(5))
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
              !focusedIssueNumbers.contains(issueNumber),
              focusedIssueNumbers.count < 5 else { return }
        focusedIssueNumbers.append(issueNumber)
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
        focusedIssueNumbers.removeAll { $0 == issueNumber }
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
        focusedIssueNumbers = order.filter(available.contains)
        saveFocus(for: repository)
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
                move(issueNumber, before: targetNumber, in: &focusedIssueNumbers)
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
            guard !focusedIssueNumbers.contains(issueNumber),
                  focusedIssueNumbers.count < 5 else { return false }
            insert(issueNumber, before: targetNumber, in: &focusedIssueNumbers)
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
            let shouldClose = destination == .closed
            let needsGitHubMutation = issue.isClosed != shouldClose
            let rollback = IssueMoveRollback(
                issue: issue,
                focusIndex: focusedIssueNumbers.firstIndex(of: issueNumber),
                openIndex: openIssueNumbers.firstIndex(of: issueNumber),
                closedIndex: closedIssueNumbers.firstIndex(of: issueNumber),
                attemptedDestination: destination
            )

            focusedIssueNumbers.removeAll { $0 == issueNumber }
            openIssueNumbers.removeAll { $0 == issueNumber }
            closedIssueNumbers.removeAll { $0 == issueNumber }
            if destination == .open {
                insert(issueNumber, before: targetNumber, in: &openIssueNumbers)
            } else {
                insert(issueNumber, before: targetNumber, in: &closedIssueNumbers)
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
            error = "GitHub could not \(close ? "close" : "reopen") issue #\(issueNumber). The move was undone."
        }
    }

    private func rollbackIssueMove(
        issueNumber: Int,
        using rollback: IssueMoveRollback
    ) {
        guard let issueIndex = issues.firstIndex(where: { $0.number == issueNumber }) else { return }
        issues[issueIndex] = rollback.issue
        focusedIssueNumbers.removeAll { $0 == issueNumber }
        openIssueNumbers.removeAll { $0 == issueNumber }
        closedIssueNumbers.removeAll { $0 == issueNumber }
        restore(issueNumber, at: rollback.focusIndex, in: &focusedIssueNumbers)
        restore(issueNumber, at: rollback.openIndex, in: &openIssueNumbers)
        restore(issueNumber, at: rollback.closedIndex, in: &closedIssueNumbers)
        if let repository = loadedRepository {
            saveSnapshot(for: repository)
            saveFocus(for: repository)
            saveBacklogOrder(for: repository)
            if rollback.focusIndex != nil {
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
        var saved = Self.savedFocus
        saved[repository] = focusedIssueNumbers
        guard let data = try? JSONEncoder().encode(saved) else { return }
        UserDefaults.standard.set(data, forKey: Self.focusedIssuesKey)
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
