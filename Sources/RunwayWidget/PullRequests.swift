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

    /// Unique across an organization: numbers repeat between repositories.
    var id: String { url.absoluteString }
    /// "VISKA-IO/monorepo", read from the URL.
    var repository: String {
        let parts = url.pathComponents
        return parts.count >= 3 ? "\(parts[1])/\(parts[2])" : ""
    }
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

    private(set) var pullRequests: [RepositoryPullRequest] = [] { didSet { revision &+= 1 } }
    /// Bumps on every change to the list, so derived indexes know to rebuild.
    @ObservationIgnored private(set) var revision = 0
    private(set) var loading = false
    private(set) var error: String?
    private(set) var hasSnapshot = false

    private var loadedRepository: String?
    private var loadTask: Task<Void, Never>?
    private var loadTaskRepository: String?
    /// True while the newest pull requests are on screen and the rest of the
    /// repository's history is still arriving.
    private(set) var catchingUpOnHistory = false
    /// How many of the newest pull requests a cold start shows before it goes
    /// back for everything.
    static let firstPaintCount = 500

    @ObservationIgnored private var snapshots = PullRequests.readSnapshots()
    @ObservationIgnored private var developerCache: [DeveloperCacheKey: [PullRequestDeveloper]] = [:]

    init() {
        Self.discoverPeople(in: snapshots.values.flatMap(\.pullRequests))
    }

    private static var snapshotFile: URL {
        RunwayStorage.supportDir.appendingPathComponent("pull-requests-cache.json")
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
            catchingUpOnHistory = false
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
        if repository.hasPrefix("org:") { return await revalidateOrganization(repository) }

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
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            // A repository's whole history is minutes of paging (monorepo is
            // past 15,000 pull requests), and the tab used to spin for all of
            // it. Put the newest few hundred on screen first and let the rest
            // arrive behind them.
            if needsFullRefresh,
               let recentData = await GH.query([
                   "pr", "list",
                   "--repo", repository,
                   "--state", "all",
                   "--limit", "\(Self.firstPaintCount)",
                   "--json", fields,
               ], cacheFor: 30),
               let recent = try? decoder.decode([RepositoryPullRequest].self, from: recentData),
               !recent.isEmpty,
               !Task.isCancelled,
               loadedRepository == repository {
                pullRequests = Self.pullRequestsAfterRefresh(
                    current: pullRequests,
                    fetched: recent,
                    fullRefresh: false
                )
                developerCache.removeAll()
                Self.discoverPeople(in: pullRequests)
                hasSnapshot = true
                catchingUpOnHistory = true
                saveSnapshot(for: repository, fetchedAt: Date(), historyComplete: false)
            }
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
            guard !Task.isCancelled, loadedRepository == repository else {
                catchingUpOnHistory = false
                return
            }
            guard let data, needsFullRefresh || open != nil else {
                // The newest ones are already on screen when this is a cold
                // start, so only a load with nothing to show is an error.
                if !hasSnapshot { error = GitHubFeed.ghHint }
                catchingUpOnHistory = false
                loading = false
                return
            }
            guard let fetched = try? decoder.decode([RepositoryPullRequest].self, from: data),
                  let fetchedOpen = try? open.map({
                      try decoder.decode([RepositoryPullRequest].self, from: $0)
                  }) ?? [] else {
                error = "Runway could not read the pull requests returned by GitHub."
                catchingUpOnHistory = false
                loading = false
                return
            }
            pullRequests = Self.pullRequestsAfterRefresh(
                current: pullRequests,
                fetched: fetched + fetchedOpen,
                fullRefresh: needsFullRefresh
            )
            applyPending(settling: true)
            developerCache.removeAll()
            Self.discoverPeople(in: pullRequests)
            hasSnapshot = true
            saveSnapshot(
                for: repository,
                fetchedAt: Date(),
                historyComplete: needsFullRefresh
                    || previousSnapshot?.historyComplete == true
            )
            catchingUpOnHistory = false
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

    // MARK: Whole organization

    /// Every PR in the organization updated this year, plus older open ones,
    /// through GitHub search. Search returns at most 1,000 results per query,
    /// so the year is cut into windows that split until each fits. Newest
    /// windows land first so the tab fills from the top.
    private func revalidateOrganization(_ scope: String) async {
        let org = String(scope.dropFirst(4))
        loading = true
        error = nil
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            let previous = snapshots[scope]
            let full = previous?.historyComplete != true
                || Date().timeIntervalSince(previous?.fetchedAt ?? .distantPast) > 7 * 86_400
            let startedAt = Date()
            var failed = false
            if full {
                let now = Date()
                let yearStart = Calendar.current.dateInterval(of: .year, for: now)?.start ?? now
                // Newest first: the last day, the last week, then week by week.
                var windows: [(Date, Date)] = [(now.addingTimeInterval(-86_400), now)]
                var end = now.addingTimeInterval(-86_400)
                while end > yearStart {
                    let start = max(end.addingTimeInterval(-7 * 86_400), yearStart)
                    windows.append((start, end))
                    end = start
                }
                for (index, window) in windows.enumerated() {
                    guard let found = await Self.searchWindow(org: org, from: window.0, to: window.1) else {
                        failed = true; break
                    }
                    guard loadedRepository == scope, !Task.isCancelled else { return }
                    pullRequests = Self.pullRequestsAfterRefresh(current: pullRequests, fetched: found, fullRefresh: false)
                    developerCache.removeAll()
                    hasSnapshot = true
                    catchingUpOnHistory = index < windows.count - 1
                }
                if !failed, let older = await Self.search("org:\(org) is:pr is:open updated:<\(Self.day(yearStart))") {
                    pullRequests = Self.pullRequestsAfterRefresh(current: pullRequests, fetched: older.pulls, fullRefresh: false)
                }
            } else {
                let since = Self.incrementalWindowStart(
                    fetchedAt: previous?.fetchedAt ?? startedAt,
                    newestUpdatedAt: previous?.pullRequests.map(\.updatedAt).max())
                if let found = await Self.searchWindow(org: org, from: since, to: startedAt.addingTimeInterval(60)) {
                    guard loadedRepository == scope else { return }
                    pullRequests = Self.pullRequestsAfterRefresh(current: pullRequests, fetched: found, fullRefresh: false)
                } else { failed = true }
            }
            guard loadedRepository == scope else { return }
            developerCache.removeAll()
            Self.discoverPeople(in: pullRequests)
            if failed, !hasSnapshot { error = GitHubFeed.ghHint }
            if !failed || hasSnapshot {
                hasSnapshot = true
                saveSnapshot(for: scope, fetchedAt: startedAt,
                             historyComplete: !failed || previous?.historyComplete == true)
            }
            catchingUpOnHistory = false
            loading = false
        }
        loadTask = task
        loadTaskRepository = scope
        await task.value
        if loadTaskRepository == scope {
            loadTask = nil
            loadTaskRepository = nil
        }
    }

    nonisolated private static func day(_ date: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withFullDate]
        return f.string(from: date)
    }

    nonisolated private static func stamp(_ date: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.string(from: date)
    }

    /// One window of `updated:` time; halves itself while GitHub reports more
    /// than search can page through.
    nonisolated private static func searchWindow(org: String, from: Date, to: Date) async -> [RepositoryPullRequest]? {
        let query = "org:\(org) is:pr updated:\(stamp(from))..\(stamp(to))"
        guard let first = await search(query, firstPageOnly: true) else { return nil }
        if first.total > 1000, to.timeIntervalSince(from) > 600 {
            let middle = from.addingTimeInterval(to.timeIntervalSince(from) / 2)
            async let a = searchWindow(org: org, from: middle, to: to)
            async let b = searchWindow(org: org, from: from, to: middle)
            guard let newer = await a, let older = await b else { return nil }
            return newer + older
        }
        if first.total <= first.pulls.count { return first.pulls }
        return await search(query)?.pulls
    }

    nonisolated private static let searchQuery = """
    query($q: String!, $cursor: String) { search(query: $q, type: ISSUE, first: 100, after: $cursor) {
      issueCount pageInfo { hasNextPage endCursor }
      nodes { ... on PullRequest {
        number title state isDraft createdAt updatedAt mergedAt closedAt url headRefName baseRefName
        author { __typename login ... on User { name } }
      } } } }
    """

    nonisolated private static func search(
        _ query: String, firstPageOnly: Bool = false
    ) async -> (total: Int, pulls: [RepositoryPullRequest])? {
        var pulls: [RepositoryPullRequest] = []
        var cursor: String?
        var total = 0
        let iso = ISO8601DateFormatter()
        for _ in 0..<10 {
            var args = ["api", "graphql", "-f", "query=\(searchQuery)", "-f", "q=\(query)"]
            if let cursor { args += ["-f", "cursor=\(cursor)"] }
            guard let data = await GH.run(args),
                  let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let result = (root["data"] as? [String: Any])?["search"] as? [String: Any]
            else { return nil }
            total = result["issueCount"] as? Int ?? 0
            for node in result["nodes"] as? [[String: Any]] ?? [] {
                guard let number = node["number"] as? Int,
                      let link = node["url"] as? String, let url = URL(string: link),
                      let created = (node["createdAt"] as? String).flatMap(iso.date(from:)),
                      let updated = (node["updatedAt"] as? String).flatMap(iso.date(from:))
                else { continue }
                let author = (node["author"] as? [String: Any]).map {
                    RepositoryPullRequest.Author(
                        login: $0["login"] as? String ?? "",
                        name: $0["name"] as? String,
                        isBot: ($0["__typename"] as? String) == "Bot")
                }
                pulls.append(RepositoryPullRequest(
                    number: number, title: node["title"] as? String ?? "",
                    state: node["state"] as? String ?? "OPEN", isDraft: node["isDraft"] as? Bool ?? false,
                    author: author, createdAt: created, updatedAt: updated,
                    mergedAt: (node["mergedAt"] as? String).flatMap(iso.date(from:)),
                    closedAt: (node["closedAt"] as? String).flatMap(iso.date(from:)),
                    url: url, headRefName: node["headRefName"] as? String ?? "",
                    baseRefName: node["baseRefName"] as? String ?? ""))
            }
            let info = result["pageInfo"] as? [String: Any]
            guard !firstPageOnly, info?["hasNextPage"] as? Bool == true,
                  let next = info?["endCursor"] as? String else { break }
            cursor = next
        }
        return (total, pulls)
    }

    /// Lay what a seat just did to a PR over the list (see ``PendingPulls``).
    /// After a real fetch, one GitHub has caught up with is let go.
    func applyPending(settling: Bool = false) {
        guard let repository = loadedRepository else { return }
        let pending = PendingPulls.shared.pulls(in: repository)
        guard !pending.isEmpty else { return }
        var next = pullRequests
        var changed = false
        for pull in pending {
            if let index = next.firstIndex(where: { $0.number == pull.number }) {
                if next[index].updatedAt >= pull.updatedAt {
                    if settling { PendingPulls.shared.settle(repository, pull.number) }
                    continue
                }
                next[index] = pull
            } else {
                next.insert(pull, at: 0)
            }
            changed = true
        }
        if changed {
            pullRequests = next
            developerCache.removeAll()
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
        var newest: [String: RepositoryPullRequest] = [:]
        for pullRequest in fetched
        where newest[pullRequest.id].map({ $0.updatedAt <= pullRequest.updatedAt }) ?? true {
            newest[pullRequest.id] = pullRequest
        }
        if fullRefresh { return newest.values.sorted(by: RepositoryPullRequest.displaySort) }
        var merged = Dictionary(
            current.map { ($0.id, $0) },
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
            at: RunwayStorage.supportDir,
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
