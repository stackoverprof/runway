import Foundation

/// One issue assigned to you in the repository on screen.
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

/// Your assigned issues, open and closed, per repository. Cached on disk so a
/// relaunch shows the last list before GitHub answers.
@MainActor @Observable final class AssignedIssues {
    private(set) var issues: [AssignedIssue] = []
    private(set) var loading = false
    private(set) var error: String?
    private(set) var hasSnapshot = false

    private struct Snapshot: Codable {
        var issues: [AssignedIssue]
        var fetchedAt: Date
    }

    @ObservationIgnored private var loadedRepository: String?
    @ObservationIgnored private var loadTask: Task<Void, Never>?
    @ObservationIgnored private var snapshots = AssignedIssues.readSnapshots()

    /// Newest first, which is how GitHub hands them over.
    var open: [AssignedIssue] {
        issues.filter { !$0.isClosed }.sorted { $0.number > $1.number }
    }

    var closed: [AssignedIssue] {
        issues.filter(\.isClosed)
            .sorted { ($0.closedAt ?? .distantPast) > ($1.closedAt ?? .distantPast) }
    }

    func restore(repository: String) {
        guard !repository.isEmpty else {
            loadTask?.cancel()
            issues = []
            loadedRepository = nil
            hasSnapshot = false
            error = nil
            return
        }
        guard loadedRepository != repository else { return }
        loadTask?.cancel()
        loadTask = nil
        loadedRepository = repository
        issues = snapshots[repository]?.issues ?? []
        hasSnapshot = snapshots[repository] != nil
        error = nil
    }

    func revalidate(repository: String, minimumAge: TimeInterval = 0) async {
        restore(repository: repository)
        guard !repository.isEmpty, loadedRepository == repository else { return }
        if minimumAge > 0,
           let fetchedAt = snapshots[repository]?.fetchedAt,
           Date().timeIntervalSince(fetchedAt) < minimumAge {
            return
        }
        if let loadTask { await loadTask.value; return }

        loading = true
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            let data = await GH.query([
                "issue", "list",
                "--repo", repository,
                "--assignee", "@me",
                "--state", "all",
                "--limit", "1000",
                "--json", "number,title,state,closedAt,createdAt,updatedAt,url",
            ], cacheFor: 30)
            guard !Task.isCancelled, loadedRepository == repository else { return }
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            guard let data else {
                if !hasSnapshot { error = GitHubFeed.ghHint }
                loading = false
                return
            }
            guard let fetched = try? decoder.decode([AssignedIssue].self, from: data) else {
                error = "Runway could not read the issues returned by GitHub."
                loading = false
                return
            }
            issues = fetched
            hasSnapshot = true
            error = nil
            snapshots[repository] = Snapshot(issues: fetched, fetchedAt: Date())
            Self.write(snapshots)
            loading = false
        }
        loadTask = task
        await task.value
        loadTask = nil
    }

    // MARK: Cache

    private static var cacheFile: URL {
        RunwayStorage.supportDir.appendingPathComponent("assigned-issues-cache.json")
    }

    private static func readSnapshots() -> [String: Snapshot] {
        guard let data = try? Data(contentsOf: cacheFile) else { return [:] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([String: Snapshot].self, from: data)) ?? [:]
    }

    private static func write(_ snapshots: [String: Snapshot]) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(snapshots) else { return }
        try? data.write(to: cacheFile)
    }
}
