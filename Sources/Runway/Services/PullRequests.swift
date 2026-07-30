import Foundation

struct RepositoryPullRequest: Codable, Identifiable, Sendable {
    struct Author: Codable, Sendable {
        let login: String
        let name: String?
        let isBot: Bool

        enum CodingKeys: String, CodingKey {
            case login, name
            case isBot = "is_bot"
        }
    }

    let number: Int
    let title: String
    let state: String
    let isDraft: Bool
    let author: Author?
    let createdAt: Date
    let updatedAt: Date
    let mergedAt: Date?
    let closedAt: Date?
    let url: URL
    let headRefName: String
    let baseRefName: String

    var id: Int { number }
    var isOpen: Bool { state == "OPEN" }
    var isMerged: Bool { mergedAt != nil || state == "MERGED" }
}

enum PullRequestDurationFormatter {
    static func string(_ duration: TimeInterval) -> String {
        let seconds = max(0, Int(duration))
        if seconds < 60 { return "open \(seconds)s" }
        let minutes = seconds / 60
        if minutes < 60 { return "open \(minutes)m" }
        let hours = minutes / 60
        if hours < 24 {
            let remainingMinutes = minutes % 60
            if remainingMinutes > 0 { return "open \(hours)h \(remainingMinutes)m" }
            return "open \(hours)h"
        }
        let days = hours / 24
        let remainingHours = hours % 24
        if remainingHours > 0 { return "open \(days)d \(remainingHours)h" }
        return "open \(days)d"
    }
}

struct PullRequestDeveloper: Identifiable {
    let login: String
    let name: String?
    let pullRequests: [RepositoryPullRequest]

    var id: String { login }
    var displayName: String {
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? login : trimmed
    }
    var openCount: Int { pullRequests.filter(\.isOpen).count }
    var mergedCount: Int { pullRequests.filter(\.isMerged).count }
    var closedCount: Int { pullRequests.count - openCount }
    var totalCount: Int { pullRequests.count }
    var avatarURL: String { "https://github.com/\(login).png?size=96" }
}

@MainActor @Observable final class PullRequests {
    static let shared = PullRequests()

    private struct DeveloperCacheKey: Hashable {
        let startMinute: Int64
        let profileRevision: Int
    }

    private(set) var pullRequests: [RepositoryPullRequest] = []
    private(set) var loading = false
    private(set) var error: String?
    private(set) var hasSnapshot = false

    private var loadedRepository: String?
    private var loadTask: Task<Void, Never>?
    private var loadTaskRepository: String?
    @ObservationIgnored private var snapshots = PullRequests.readSnapshots()
    @ObservationIgnored private var developerCache: [DeveloperCacheKey: [PullRequestDeveloper]] = [:]

    init() {
        Self.discoverPeople(in: snapshots.values.flatMap(\.pullRequests))
    }

    private static var snapshotFile: URL {
        AgentControl.supportDir.appendingPathComponent("pull-requests-cache.json")
    }

    var developers: [PullRequestDeveloper] { developers(since: nil) }

    func developers(since startDate: Date?) -> [PullRequestDeveloper] {
        let startMinute = startDate.map { Int64($0.timeIntervalSince1970 / 60) } ?? -1
        let key = DeveloperCacheKey(
            startMinute: startMinute,
            profileRevision: PersonProfileManager.shared.revision
        )
        if let cached = developerCache[key] { return cached }
        let humanPullRequests = pullRequests.filter { pr in
            guard let author = pr.author else { return false }
            return !author.isBot
                && !author.login.isEmpty
                && startDate.map { pr.createdAt >= $0 } != false
        }
        let developers = Dictionary(grouping: humanPullRequests) { $0.author!.login }
            .map { login, pullRequests in
                let author = pullRequests.first?.author
                let profileName = PersonProfileManager.shared.fullName(for: login)
                return PullRequestDeveloper(
                    login: login,
                    name: profileName == login ? author?.name : profileName,
                    pullRequests: pullRequests.sorted(by: Self.pullRequestSort)
                )
            }
            .sorted { lhs, rhs in
                if lhs.mergedCount != rhs.mergedCount { return lhs.mergedCount > rhs.mergedCount }
                if lhs.totalCount != rhs.totalCount { return lhs.totalCount > rhs.totalCount }
                return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
            }
        developerCache[key] = developers
        return developers
    }

    func restore(repository: String) {
        guard !repository.isEmpty else {
            loadTask?.cancel()
            pullRequests = []
            developerCache.removeAll()
            loadedRepository = nil
            hasSnapshot = false
            error = nil
            return
        }
        guard loadedRepository != repository else { return }
        loadTask?.cancel()
        loadTask = nil
        loadTaskRepository = nil
        loadedRepository = repository
        pullRequests = snapshots[repository]?.pullRequests ?? []
        developerCache.removeAll()
        Self.discoverPeople(in: pullRequests)
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
        if let loadTask, loadTaskRepository == repository {
            await loadTask.value
            return
        }

        loading = true
        error = nil
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            let previousSnapshot = snapshots[repository]
            let cacheAge = previousSnapshot.map {
                Date().timeIntervalSince($0.fetchedAt)
            } ?? .infinity
            let needsFullRefresh = previousSnapshot?.historyComplete != true
                || cacheAge > 90 * 86_400
            var arguments = [
                "pr", "list",
                "--repo", repository,
                "--state", "all",
                "--limit", needsFullRefresh ? "20000" : "1000",
                "--json",
                "number,title,state,isDraft,author,createdAt,updatedAt,mergedAt,closedAt,url,headRefName,baseRefName",
            ]
            if !needsFullRefresh, let fetchedAt = previousSnapshot?.fetchedAt {
                let overlapStart = fetchedAt.addingTimeInterval(-300)
                arguments.append(contentsOf: [
                    "--search",
                    "updated:>=\(Self.iso8601.string(from: overlapStart))",
                ])
            }
            let data = await GH.query(arguments, cacheFor: 30)
            guard !Task.isCancelled, loadedRepository == repository else { return }
            guard let data else {
                error = GitHubFeed.ghHint
                loading = false
                return
            }
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            guard let fetched = try? decoder.decode([RepositoryPullRequest].self, from: data) else {
                error = "Runway could not read the pull requests returned by GitHub."
                loading = false
                return
            }
            if needsFullRefresh {
                pullRequests = fetched.sorted(by: Self.pullRequestSort)
            } else {
                var merged = Dictionary(
                    uniqueKeysWithValues: pullRequests.map { ($0.number, $0) }
                )
                for pullRequest in fetched {
                    merged[pullRequest.number] = pullRequest
                }
                pullRequests = merged.values.sorted(by: Self.pullRequestSort)
            }
            developerCache.removeAll()
            Self.discoverPeople(in: pullRequests)
            hasSnapshot = true
            saveSnapshot(
                for: repository,
                fetchedAt: Date(),
                historyComplete: needsFullRefresh
                    || previousSnapshot?.historyComplete == true
            )
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

    private static func pullRequestSort(
        _ lhs: RepositoryPullRequest,
        _ rhs: RepositoryPullRequest
    ) -> Bool {
        if lhs.isOpen != rhs.isOpen { return lhs.isOpen }
        if lhs.isMerged != rhs.isMerged { return lhs.isMerged }
        return lhs.updatedAt > rhs.updatedAt
    }

    static func discoverCachedPeople() {
        discoverPeople(in: readSnapshots().values.flatMap(\.pullRequests))
    }

    private static func discoverPeople(in pullRequests: [RepositoryPullRequest]) {
        var identities: [String: RepositoryPullRequest.Author] = [:]
        for pullRequest in pullRequests {
            guard let author = pullRequest.author, !author.login.isEmpty else { continue }
            identities[author.login.lowercased()] = author
        }
        PersonProfileManager.shared.discover(identities.values.map { author in
            (
                login: author.login,
                githubFullName: author.name,
                avatarURL: "https://github.com/\(author.login).png?size=96"
            )
        })
    }

    private func saveSnapshot(
        for repository: String,
        fetchedAt: Date,
        historyComplete: Bool
    ) {
        snapshots[repository] = CachedRepository(
            pullRequests: pullRequests,
            fetchedAt: fetchedAt,
            historyComplete: historyComplete
        )
        guard let data = try? Self.encoder.encode(snapshots) else { return }
        try? FileManager.default.createDirectory(
            at: AgentControl.supportDir,
            withIntermediateDirectories: true
        )
        try? data.write(to: Self.snapshotFile, options: .atomic)
    }

    private struct CachedRepository: Codable {
        let pullRequests: [RepositoryPullRequest]
        let fetchedAt: Date
        let historyComplete: Bool?
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    private static let iso8601 = ISO8601DateFormatter()

    private static func readSnapshots() -> [String: CachedRepository] {
        guard let data = try? Data(contentsOf: snapshotFile),
              let snapshots = try? decoder.decode(
                [String: CachedRepository].self,
                from: data
              ) else { return [:] }
        return snapshots
    }
}
