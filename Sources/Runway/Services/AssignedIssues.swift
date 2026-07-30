import Foundation

struct AssignedIssue: Codable, Identifiable, Sendable {
    let number: Int
    let title: String
    var state: String
    var closedAt: Date?
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
            let data = await GH.run([
                "issue", "list",
                "--repo", repository,
                "--assignee", "@me",
                "--state", "all",
                "--limit", "1000",
                "--json", "number,title,state,closedAt,url",
            ])
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
            issues = fetched
            hasSnapshot = true
            reconcileOrders(with: fetched)
            saveSnapshot(for: repository, fetchedAt: Date())
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

    private func reconcileOrders(with availableIssues: [AssignedIssue]) {
        let defaultOpen = availableIssues.filter { !$0.isClosed }.map(\.number)
        let defaultClosed = availableIssues
            .filter(\.isClosed)
            .sorted { ($0.closedAt ?? .distantPast) > ($1.closedAt ?? .distantPast) }
            .map(\.number)
        openIssueNumbers = Self.mergedOrder(openIssueNumbers, available: defaultOpen)
        closedIssueNumbers = Self.mergedOrder(closedIssueNumbers, available: defaultClosed)
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
        openIssueNumbers = issues.filter { !$0.isClosed }.map(\.number)
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
    }

    func removeFromFocus(issueNumber: Int) {
        guard let repository = loadedRepository else { return }
        focusedIssueNumbers.removeAll { $0 == issueNumber }
        saveFocus(for: repository)
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
            return true

        case (.focus, .open), (.focus, .closed):
            let shouldClose = destination == .closed
            let needsGitHubMutation = issue.isClosed != shouldClose
            let rollback = IssueMoveRollback(
                issue: issue,
                focusIndex: focusedIssueNumbers.firstIndex(of: issueNumber),
                openIndex: openIssueNumbers.firstIndex(of: issueNumber),
                closedIndex: closedIssueNumbers.firstIndex(of: issueNumber)
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

    private func saveSnapshot(for repository: String, fetchedAt: Date? = nil) {
        let validationDate = fetchedAt
            ?? snapshots[repository]?.fetchedAt
            ?? .distantPast
        snapshots[repository] = CachedRepository(
            issues: issues,
            fetchedAt: validationDate
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
    }

    private struct CachedRepository: Codable {
        let issues: [AssignedIssue]
        let fetchedAt: Date
    }

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

    private static func mergedOrder(_ saved: [Int], available: [Int]) -> [Int] {
        let availableSet = Set(available)
        let retained = saved.filter(availableSet.contains)
        let retainedSet = Set(retained)
        return retained + available.filter { !retainedSet.contains($0) }
    }
}
