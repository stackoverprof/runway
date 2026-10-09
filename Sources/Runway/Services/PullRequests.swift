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
    /// The timestamp represented by the Pulls timeframe for this PR's current
    /// state. A merge belongs to the day it merged, not the day it was opened.
    var timeframeDate: Date {
        if isMerged { return mergedAt ?? closedAt ?? updatedAt }
        if isOpen { return createdAt }
        return closedAt ?? updatedAt
    }

    static func displaySort(
        _ lhs: RepositoryPullRequest,
        _ rhs: RepositoryPullRequest
    ) -> Bool {
        let lhsCategory = displayCategory(lhs)
        let rhsCategory = displayCategory(rhs)
        if lhsCategory != rhsCategory { return lhsCategory < rhsCategory }

        let lhsDate = displaySortDate(lhs)
        let rhsDate = displaySortDate(rhs)
        if lhsDate != rhsDate { return lhsDate > rhsDate }
        return lhs.number > rhs.number
    }

    private static func displayCategory(_ pullRequest: RepositoryPullRequest) -> Int {
        if pullRequest.isOpen && pullRequest.isDraft { return 0 }
        if pullRequest.isOpen && !pullRequest.isDraft { return 1 }
        if pullRequest.isMerged { return 2 }
        return 3
    }

    private static func displaySortDate(_ pullRequest: RepositoryPullRequest) -> Date {
        if pullRequest.isOpen { return pullRequest.createdAt }
        if pullRequest.isMerged {
            return pullRequest.mergedAt ?? pullRequest.closedAt ?? pullRequest.updatedAt
        }
        return pullRequest.closedAt ?? pullRequest.updatedAt
    }
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
    var openCount: Int { pullRequests.filter { $0.isOpen && !$0.isDraft }.count }
    var draftCount: Int { pullRequests.filter { $0.isOpen && $0.isDraft }.count }
    var mergedCount: Int { pullRequests.filter(\.isMerged).count }
    var closedCount: Int {
        pullRequests.filter { !$0.isOpen && !$0.isMerged }.count
    }
    var totalCount: Int { pullRequests.count }
    var avatarURL: String { "https://github.com/\(login).png?size=96" }

    static func ranksAbove(
        _ lhs: PullRequestDeveloper,
        _ rhs: PullRequestDeveloper,
        displayName: (PullRequestDeveloper) -> String = { $0.displayName }
    ) -> Bool {
        if lhs.mergedCount != rhs.mergedCount { return lhs.mergedCount > rhs.mergedCount }
        // An open PR counts twice as much as a draft. Keep open PRs ahead
        // when the weighted totals tie, then use other activity as a tiebreaker.
        let lhsActiveScore = lhs.openCount * 2 + lhs.draftCount
        let rhsActiveScore = rhs.openCount * 2 + rhs.draftCount
        if lhsActiveScore != rhsActiveScore { return lhsActiveScore > rhsActiveScore }
        if lhs.openCount != rhs.openCount { return lhs.openCount > rhs.openCount }
        if lhs.totalCount != rhs.totalCount { return lhs.totalCount > rhs.totalCount }
        return displayName(lhs).localizedCaseInsensitiveCompare(displayName(rhs)) == .orderedAscending
    }
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
                && startDate.map { pr.timeframeDate >= $0 } != false
        }
        let developers = Dictionary(grouping: humanPullRequests) { $0.author!.login }
            .map { login, pullRequests in
                let author = pullRequests.first?.author
                let profileName = PersonProfileManager.shared.fullName(for: login)
                return PullRequestDeveloper(
                    login: login,
                    name: profileName == login ? author?.name : profileName,
                    pullRequests: pullRequests.sorted(by: RepositoryPullRequest.displaySort)
                )
            }
            .sorted { PullRequestDeveloper.ranksAbove($0, $1) }
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
            let fields = "number,title,state,isDraft,author,createdAt,updatedAt,mergedAt,closedAt,url,headRefName,baseRefName"
            var arguments = [
                "pr", "list",
                "--repo", repository,
                "--state", "all",
                "--limit", needsFullRefresh ? "20000" : "1000",
                "--json", fields,
            ]
            if !needsFullRefresh, let fetchedAt = previousSnapshot?.fetchedAt {
                let windowStart = Self.incrementalWindowStart(
                    fetchedAt: fetchedAt,
                    newestUpdatedAt: previousSnapshot?.pullRequests.map(\.updatedAt).max()
                )
                arguments.append(contentsOf: [
                    "--search",
                    "updated:>=\(Self.iso8601.string(from: windowStart))",
                ])
            }
            // The search window rides GitHub's search index, which can lag a
            // fresh edit like a retitle. Open PRs are the ones that get renamed,
            // so an incremental refresh also lists them without search.
            async let windowData = GH.query(arguments, cacheFor: 30)
            async let openData: Data? = needsFullRefresh ? nil : GH.query([
                "pr", "list",
                "--repo", repository,
                "--state", "open",
                "--limit", "1000",
                "--json", fields,
            ], cacheFor: 30)
            let (data, open) = await (windowData, openData)
            guard !Task.isCancelled, loadedRepository == repository else { return }
            guard let data, needsFullRefresh || open != nil else {
                error = GitHubFeed.ghHint
                loading = false
                return
            }
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            guard let fetched = try? decoder.decode([RepositoryPullRequest].self, from: data),
                  let fetchedOpen = try? open.map({
                      try decoder.decode([RepositoryPullRequest].self, from: $0)
                  }) ?? [] else {
                error = "Runway could not read the pull requests returned by GitHub."
                loading = false
                return
            }
            pullRequests = Self.pullRequestsAfterRefresh(
                current: pullRequests,
                fetched: fetched + fetchedOpen,
                fullRefresh: needsFullRefresh
            )
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

    /// Where an incremental search starts. Anchored on the newest edit already
    /// cached as well as the last fetch, with an hour of overlap, so a search
    /// index that lags an edit gets several more chances to return it. Never
    /// reaches more than a day back, which keeps quiet repos cheap.
    nonisolated static func incrementalWindowStart(fetchedAt: Date, newestUpdatedAt: Date?) -> Date {
        let anchored = min(fetchedAt, newestUpdatedAt ?? fetchedAt).addingTimeInterval(-3_600)
        return max(anchored, fetchedAt.addingTimeInterval(-86_400))
    }

    /// Merges fetched PRs over the cache. A PR can arrive from both the search
    /// window and the open list, so the most recently updated copy wins.
    nonisolated static func pullRequestsAfterRefresh(
        current: [RepositoryPullRequest],
        fetched: [RepositoryPullRequest],
        fullRefresh: Bool
    ) -> [RepositoryPullRequest] {
        var newest: [Int: RepositoryPullRequest] = [:]
        for pullRequest in fetched
        where newest[pullRequest.number].map({ $0.updatedAt <= pullRequest.updatedAt }) ?? true {
            newest[pullRequest.number] = pullRequest
        }
        if fullRefresh { return newest.values.sorted(by: RepositoryPullRequest.displaySort) }
        var merged = Dictionary(
            current.map { ($0.number, $0) },
            uniquingKeysWith: { $1 }
        )
        merged.merge(newest) { $1 }
        return merged.values.sorted(by: RepositoryPullRequest.displaySort)
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
