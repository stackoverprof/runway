import SwiftUI
import Foundation

// MARK: - Models

enum FeedKind: Codable, Equatable {
    case push(branch: String, count: Int?, commits: [Commit])
    case prOpened(number: Int, title: String, branch: String)
    case prMerged(number: Int, title: String, base: String, branch: String, additions: Int?, deletions: Int?, commits: Int?, duration: TimeInterval?)
    case branchCreated(String)
    case branchDeleted(String)
    case review(number: Int, title: String, state: String)
    case issueOpened(number: Int, title: String)
    case issueClosed(number: Int, title: String)

    struct Commit: Identifiable, Codable, Equatable {
        var id: String { sha }
        let sha: String; let message: String
        enum CodingKeys: String, CodingKey { case sha, message }   // id is computed
    }
}

struct FeedEvent: Identifiable, Codable, Equatable {
    let id: String
    let actor: String
    let avatarURL: String?
    let date: Date
    let kind: FeedKind
}

struct Presence: Identifiable {
    var id: String { login }
    let login: String
    let avatarURL: String?
    let lastActive: Date
    let recentCount: Int      // events in the last 30 min ("intensity")
    var idle: Bool            // no activity for > 30 min
}

// MARK: - Feed (polls the GitHub API via the user's `gh` CLI)

@MainActor @Observable final class GitHubFeed {
    static let shared = GitHubFeed()

    var repo: String = UserDefaults.standard.string(forKey: "runway.repo") ?? ""
    var availableRepos: [String] = []
    private(set) var repositoryPaths: [String: String] = [:]
    var events: [FeedEvent] = []
    var presence: [Presence] = []
    var lastError: String?
    var loading = false
    /// True once a fetch has succeeded, so the UI can tell "still loading"
    /// (skeleton) apart from "loaded, nothing here" (empty notice).
    var didLoad = false
    /// Infinite scroll: whether more pages may exist + an in-flight guard.
    var canLoadMore = true
    var loadingMore = false
    private var loadedPages = 1
    @ObservationIgnored private var refreshing = false
    private var offline = false   // for the offline/online toast transition
    /// Commit counts for pushes (this events API strips `size`), keyed by
    /// "before...head" and fetched via the compare API, with an in-flight guard.
    private var commitCounts: [String: Int] = [:]
    private var pushSHAs: [String: (before: String, head: String)] = [:]
    private var fetchingCounts: Set<String> = []
    private var fetchingPRs: Set<Int> = []
    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private var repoListTask: Task<Void, Never>?
    /// Walking the home directory and asking git for each remote is expensive,
    /// so background revalidation is throttled to this interval.
    private static let repositoryScanInterval: TimeInterval = 120
    @ObservationIgnored private var lastRepositoryScanAt: Date?
    @ObservationIgnored private var repositoryListHeld = false
    @ObservationIgnored private var pendingRepositoryDirectory:
        (repositories: [String], paths: [String: String])?

    /// User-facing hint shown when `gh` can't be reached (missing or not signed in).
    static let ghHint = "Can't reach GitHub. Make sure the GitHub CLI is installed and you're signed in: run `gh auth login` in a terminal."

    /// Seconds between automatic polls (Settings, default 45).
    var pollInterval: UInt64 { UInt64(max(5, UserDefaults.standard.integer(forKey: SettingsKey.pollInterval))) }
    /// How long without activity counts as idle (Settings, default 30 min).
    private var idleThreshold: TimeInterval { TimeInterval(max(1, UserDefaults.standard.integer(forKey: SettingsKey.idleMinutes)) * 60) }
    private let isoFull = ISO8601DateFormatter()

    // Disk cache so reopening the app shows the last feed instantly (no skeleton).
    /// v2 because caches written before events were filed per repository can hold
    /// another repository's events under this one's key. A cached event carries no
    /// repository of its own, so a mixed entry cannot be repaired, only dropped.
    private static var cacheFile: URL {
        AgentControl.supportDir.appendingPathComponent("feed-cache.v2.json")
    }
    private static var legacyCacheFile: URL {
        AgentControl.supportDir.appendingPathComponent("feed-cache.json")
    }
    /// Runs once per launch, before the first cache read.
    private static let discardLegacyCache: Void = {
        guard FileManager.default.fileExists(atPath: legacyCacheFile.path) else { return }
        try? FileManager.default.removeItem(at: legacyCacheFile)
        // Without this the first poll could skip its fetch as "recently
        // validated" and leave the freshly emptied feed on a skeleton.
        UserDefaults.standard.removeObject(forKey: feedValidatedAtKey)
    }()
    private static let recentRepositoriesKey = "runway.recentRepositories.v1"
    private static let repositoryDirectoryKey = "runway.repositoryDirectory.v1"
    private static let repositoryPathsKey = "runway.repositoryPaths.v1"
    private static let feedValidatedAtKey = "runway.feedValidatedAt.v1"
    private static let coderDate: JSONEncoder = { let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; return e }()
    private static let decoderDate: JSONDecoder = { let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d }()

    init() {
        Self.discardLegacyCache
        repositoryPaths = Self.cachedRepositoryPaths.filter {
            FileManager.default.fileExists(atPath: URL(fileURLWithPath: $0.value)
                .appendingPathComponent(".git").path)
        }
        availableRepos = Self.cachedRepositoryDirectory.filter {
            Self.path(for: $0, in: repositoryPaths) != nil
        }
        if !repositoryPaths.isEmpty, Self.path(for: repo, in: repositoryPaths) == nil {
            repo = availableRepos.first ?? ""
            UserDefaults.standard.set(repo, forKey: "runway.repo")
        }
        loadCache()
    }

    /// Filter out branch-delete and merge-commit noise from the visible feed.
    static func filterNoise(_ events: [FeedEvent]) -> [FeedEvent] {
        let mergeTargets: [(branch: String, date: Date)] = events.compactMap { event in
            if case let .prMerged(_, _, base, _, _, _, _, _) = event.kind {
                return (base, event.date)
            }
            return nil
        }
        return events.filter { event in
            switch event.kind {
            case .branchDeleted:
                return false
            case let .push(branch, _, _):
                return !mergeTargets.contains { target in
                    target.branch == branch
                        && abs(target.date.timeIntervalSince(event.date)) < 120
                }
            default:
                return true
            }
        }
    }

    /// Load the cached feed for the current repo (if any) so the left pane renders
    /// immediately instead of a skeleton. Recomputes presence from it.
    private func loadCache() {
        didLoad = false; events = []; presence = []
        guard let data = try? Data(contentsOf: Self.cacheFile),
              let byRepo = try? Self.decoderDate.decode([String: [FeedEvent]].self, from: data),
              let cached = byRepo[repo], !cached.isEmpty else { return }
        events = cached.sorted { $0.date > $1.date }
        presence = computePresence(from: events)
        Self.discoverPeople(in: events)
        didLoad = true
    }

    /// Delete the on-disk feed cache and refetch the current repo.
    static func clearCache() {
        try? FileManager.default.removeItem(at: cacheFile)
        UserDefaults.standard.removeObject(forKey: feedValidatedAtKey)
        shared.events = []; shared.presence = []; shared.didLoad = false
        Task { await shared.refresh() }
    }

    /// The cache is keyed by repository, so the owning repository travels with
    /// the events instead of being read from `repo` at write time. Reading it
    /// late is how one repository's events used to be filed under another.
    private func saveCache(_ list: [FeedEvent], for repository: String) {
        guard !repository.isEmpty else { return }
        var byRepo = (try? Data(contentsOf: Self.cacheFile))
            .flatMap { try? Self.decoderDate.decode([String: [FeedEvent]].self, from: $0) } ?? [:]
        byRepo[repository] = Array(list.prefix(1000))   // cap per repo
        if let data = try? Self.coderDate.encode(byRepo) { try? data.write(to: Self.cacheFile) }
    }

    func startPolling() {
        guard pollTask == nil else { return }
        fetchRepoList()        // cached list, instantly
        revalidateRepoList()   // then bring it up to date before it is opened
        pollTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let interval = self.pollInterval
                if NSApp.isActive {
                    if self.repo.isEmpty { self.fetchRepoList() }
                    self.revalidateRepoList()
                    await self.refresh(minimumAge: TimeInterval(interval))
                }
                do {
                    try await Task.sleep(nanoseconds: interval * 1_000_000_000)
                } catch {
                    return
                }
            }
        }
    }

    func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
        repoListTask?.cancel()
        repoListTask = nil
    }

    func setRepo(_ r: String) {
        guard r != repo, localPath(for: r) != nil else { return }
        repo = r
        UserDefaults.standard.set(r, forKey: "runway.repo")
        Self.rememberRepository(r)
        presence = []; lastError = nil; loadedPages = 1; canLoadMore = true
        loadCache()   // show this repo's cached feed instantly (or skeleton if none)
        Task { await refresh() }
    }

    func localPath(for repository: String) -> String? {
        Self.path(for: repository, in: repositoryPaths)
            ?? LocalRepositoryDirectory.directCheckoutPath(for: repository)
    }

    /// Find cloned GitHub repositories under the configured local repository root.
    func fetchRepoList(force: Bool = false) {
        if !force, !availableRepos.isEmpty { return }
        guard repoListTask == nil else { return }
        lastRepositoryScanAt = Date()
        repoListTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.repoListTask = nil }
            let localRepositories = await Task.detached(priority: .utility) {
                LocalRepositoryDirectory.discoverOnDevice()
            }.value
            let paths = Dictionary(uniqueKeysWithValues: localRepositories.map {
                ($0.nameWithOwner, $0.path)
            })
            let repos = localRepositories.map(\.nameWithOwner)
            // Whatever is already listed keeps its position: a rescan may only
            // append clones that appeared and drop clones that vanished. The
            // current-then-recent ranking therefore applies to the first build
            // only, so the picker never reshuffles rows a user is reading.
            let ordered = Self.uniqueRepositories(
                self.availableRepos + [self.repo] + Self.recentRepositories + repos
            ).filter {
                Self.path(for: $0, in: paths) != nil
            }
            self.applyRepositoryDirectory(ordered, paths: paths)
        }
    }

    /// Rescan for cloned repositories ahead of time, throttled. The picker only
    /// ever renders the result of an earlier scan, so the scan has to happen
    /// while it is closed. A scan landing under an open list is what made the
    /// rows jump a second after opening.
    func revalidateRepoList() {
        if let lastRepositoryScanAt,
           Date().timeIntervalSince(lastRepositoryScanAt) < Self.repositoryScanInterval {
            return
        }
        fetchRepoList(force: true)
    }

    /// Freeze the repository list while the picker is on screen. A scan that
    /// finishes meanwhile parks its result and lands once the list closes.
    func holdRepositoryList(_ held: Bool) {
        repositoryListHeld = held
        guard !held, let pending = pendingRepositoryDirectory else { return }
        pendingRepositoryDirectory = nil
        applyRepositoryDirectory(pending.repositories, paths: pending.paths)
    }

    private func applyRepositoryDirectory(
        _ ordered: [String],
        paths: [String: String]
    ) {
        if repositoryListHeld {
            pendingRepositoryDirectory = (repositories: ordered, paths: paths)
            return
        }
        repositoryPaths = paths
        availableRepos = ordered
        Self.saveRepositoryDirectory(ordered, paths: paths)
        if !ordered.isEmpty {
            if Self.path(for: repo, in: paths) == nil, let first = ordered.first {
                setRepo(first)
            }
        } else {
            repo = ""
            UserDefaults.standard.set("", forKey: "runway.repo")
            events = []
            presence = []
            didLoad = false
            lastError = "No cloned GitHub repositories found on this Mac."
        }
    }

    private static var cachedRepositoryDirectory: [String] {
        UserDefaults.standard.stringArray(forKey: repositoryDirectoryKey) ?? []
    }

    private static var cachedRepositoryPaths: [String: String] {
        UserDefaults.standard.dictionary(forKey: repositoryPathsKey) as? [String: String] ?? [:]
    }

    private static func saveRepositoryDirectory(
        _ repositories: [String],
        paths: [String: String]
    ) {
        UserDefaults.standard.set(repositories, forKey: repositoryDirectoryKey)
        UserDefaults.standard.set(paths, forKey: repositoryPathsKey)
    }

    private static var recentRepositories: [String] {
        UserDefaults.standard.stringArray(forKey: recentRepositoriesKey) ?? []
    }

    private static func rememberRepository(_ repository: String) {
        guard !repository.isEmpty else { return }
        let key = repository.lowercased()
        let recent = [repository] + recentRepositories.filter {
            $0.lowercased() != key
        }
        UserDefaults.standard.set(Array(recent.prefix(20)), forKey: recentRepositoriesKey)
    }

    private static func uniqueRepositories(_ repositories: [String]) -> [String] {
        var seen = Set<String>()
        return repositories.filter { repository in
            !repository.isEmpty && seen.insert(repository.lowercased()).inserted
        }
    }

    private static func path(
        for repository: String,
        in paths: [String: String]
    ) -> String? {
        let key = repository.lowercased()
        return paths.first { $0.key.lowercased() == key }?.value
    }

    func refresh(minimumAge: TimeInterval = 0) async {
        // Everything below belongs to the repository selected when the fetch
        // started. A switch mid-flight makes the response someone else's data.
        let repository = repo
        guard !repository.isEmpty, !refreshing else { return }
        if minimumAge > 0,
           Date().timeIntervalSince(Self.validationDate(for: repository)) < minimumAge {
            return
        }
        refreshing = true
        defer { refreshing = false }
        loading = events.isEmpty
        guard let page = await fetchPage(1, in: repository) else {
            guard repo == repository else { return dropStaleRefresh() }
            if !offline {
                offline = true
            }
            lastError = Self.ghHint; loading = false; return
        }
        guard repo == repository else { return dropStaleRefresh() }
        if offline {
            offline = false
        }
        merge(page.events, in: repository, staggerNew: true)
        canLoadMore = page.full
        fetchCommitCounts(in: repository)
        fetchPRDetails(in: repository)
        Self.recordValidationDate(for: repository)
        lastError = nil
        didLoad = true
        loading = false
    }

    /// The selected repository changed while a page was in flight. Throw the
    /// response away and fetch the repository that is actually on screen, which
    /// the in-flight guard would otherwise have skipped.
    private func dropStaleRefresh() {
        loading = false
        Task { @MainActor [weak self] in await self?.refresh() }
    }

    private static func validationDate(for repository: String) -> Date {
        let values = UserDefaults.standard.dictionary(forKey: feedValidatedAtKey)
        let timestamp = values?[repository] as? Double ?? 0
        return Date(timeIntervalSince1970: timestamp)
    }

    private static func recordValidationDate(for repository: String) {
        var values = UserDefaults.standard.dictionary(forKey: feedValidatedAtKey) ?? [:]
        values[repository] = Date().timeIntervalSince1970
        UserDefaults.standard.set(values, forKey: feedValidatedAtKey)
    }

    /// Load the next page of older events (infinite scroll). The events API is
    /// capped at ~300 events, so this naturally stops when GitHub runs out.
    func loadMore() async {
        let repository = repo
        guard didLoad, canLoadMore, !loadingMore, !repository.isEmpty else { return }
        loadingMore = true
        defer { loadingMore = false }
        let next = loadedPages + 1
        guard let page = await fetchPage(next, in: repository), !page.events.isEmpty else {
            guard repo == repository else { return }
            canLoadMore = false; return
        }
        guard repo == repository else { return }
        merge(page.events, in: repository)
        loadedPages = next
        canLoadMore = page.full
        fetchCommitCounts(in: repository)
        fetchPRDetails(in: repository)
    }

    /// Fill in commit counts for pushes that don't have one yet, via the compare
    /// API (cached by range + an in-flight set so each range is fetched once).
    private func fetchCommitCounts(in repository: String) {
        for e in events {
            guard case let .push(_, count, _) = e.kind, count == nil,
                  let shas = pushSHAs[e.id] else { continue }
            let key = "\(shas.before)...\(shas.head)"
            if let cached = commitCounts[key] { applyCount(cached, to: e.id); continue }
            if fetchingCounts.contains(key) { continue }
            fetchingCounts.insert(key)
            Task { @MainActor in
                defer { fetchingCounts.remove(key) }
                guard let data = await GH.api(
                    "/repos/\(repository)/compare/\(key)",
                    cacheFor: 24 * 3_600
                ),
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let total = json["total_commits"] as? Int else { return }
                commitCounts[key] = total
                guard repo == repository else { return }
                applyCount(total, to: e.id)
            }
        }
    }

    private func applyCount(_ count: Int, to id: String) {
        guard let i = events.firstIndex(where: { $0.id == id }),
              case let .push(branch, _, commits) = events[i].kind else { return }
        let old = events[i]
        events[i] = FeedEvent(id: old.id, actor: old.actor, avatarURL: old.avatarURL,
                              date: old.date, kind: .push(branch: branch, count: count, commits: commits))
    }

    private func fetchPRDetails(in repository: String) {
        for e in events {
            guard case let .prMerged(num, _, _, _, _, _, commits, _) = e.kind,
                  commits == nil else { continue }
            if fetchingPRs.contains(num) { continue }
            fetchingPRs.insert(num)

            Task { @MainActor in
                defer { fetchingPRs.remove(num) }
                guard let data = await GH.api(
                    "/repos/\(repository)/pulls/\(num)",
                    cacheFor: 24 * 3_600
                ),
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
                
                let additions = json["additions"] as? Int ?? 0
                let deletions = json["deletions"] as? Int ?? 0
                let commitsCount = json["commits"] as? Int ?? 0
                
                let createdStr = json["created_at"] as? String ?? ""
                let mergedStr = json["merged_at"] as? String ?? json["closed_at"] as? String ?? ""
                
                let df = ISO8601DateFormatter()
                let created = df.date(from: createdStr) ?? Date()
                let merged = df.date(from: mergedStr) ?? Date()
                let duration = merged.timeIntervalSince(created)
                
                guard repo == repository else { return }
                applyPRDetails(
                    number: num,
                    additions: additions,
                    deletions: deletions,
                    commits: commitsCount,
                    duration: duration,
                    in: repository
                )
            }
        }
    }

    private func applyPRDetails(
        number: Int,
        additions: Int,
        deletions: Int,
        commits: Int,
        duration: TimeInterval,
        in repository: String
    ) {
        for i in 0..<events.count {
            if case let .prMerged(num, title, base, branch, _, _, _, _) = events[i].kind, num == number {
                let old = events[i]
                events[i] = FeedEvent(
                    id: old.id,
                    actor: old.actor,
                    avatarURL: old.avatarURL,
                    date: old.date,
                    kind: .prMerged(
                        number: num,
                        title: title,
                        base: base,
                        branch: branch,
                        additions: additions,
                        deletions: deletions,
                        commits: commits,
                        duration: duration
                    )
                )
            }
        }
        saveCache(events, for: repository)
    }

    private func fetchPage(
        _ page: Int,
        in repository: String
    ) async -> (events: [FeedEvent], full: Bool)? {
        guard let data = await GH.api(
            "/repos/\(repository)/events?per_page=100&page=\(page)",
            cacheFor: page == 1 ? 10 : 60 * 60
        ),
              let raw = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return nil }
        let hideBots = UserDefaults.standard.bool(forKey: SettingsKey.hideBots)
        let parsed = raw.compactMap(parse).filter { !(hideBots && $0.actor.hasSuffix("[bot]")) }
        return (parsed, raw.count >= 100)
    }

    private func mergeEvent(_ old: FeedEvent, _ new: FeedEvent) -> FeedEvent {
        if case let .push(branch, oldCount, commits) = old.kind,
           case let .push(_, newCount, _) = new.kind {
            let count = newCount ?? oldCount
            return FeedEvent(id: new.id, actor: new.actor, avatarURL: new.avatarURL, date: new.date,
                             kind: .push(branch: branch, count: count, commits: commits))
        }
        if case let .prMerged(num, title, base, branch, oldAdds, oldDels, oldCommits, oldDur) = old.kind,
           case let .prMerged(_, _, _, _, newAdds, newDels, newCommits, newDur) = new.kind {
            let additions = newAdds ?? oldAdds
            let deletions = newDels ?? oldDels
            let commits = newCommits ?? oldCommits
            let duration = newDur ?? oldDur
            return FeedEvent(id: new.id, actor: new.actor, avatarURL: new.avatarURL, date: new.date,
                             kind: .prMerged(number: num, title: title, base: base, branch: branch,
                                             additions: additions, deletions: deletions,
                                             commits: commits, duration: duration))
        }
        return new
    }

    /// Merge new events (deduped by id, newest first), recompute presence, cache.
    /// With `staggerNew`, brand-new events at the top reveal one-by-one (phone-
    /// notification style): older cards slide down as each new one fades in.
    private func merge(
        _ incoming: [FeedEvent],
        in repository: String,
        staggerNew: Bool = false,
        persistCache: Bool = true,
        animateFromEmpty: Bool = false
    ) {
        let existing = Set(events.map(\.id))
        var byID = [String: FeedEvent](minimumCapacity: events.count + incoming.count)
        for e in events { byID[e.id] = e }
        for e in incoming {
            if let old = byID[e.id] {
                byID[e.id] = mergeEvent(old, e)
            } else {
                byID[e.id] = e
            }
        }
        let full = byID.values.sorted { $0.date > $1.date }
        Self.discoverPeople(in: full)
        let hadEvents = !events.isEmpty

        let nextPresence = computePresence(from: full)
        if hadEvents || animateFromEmpty {
            withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) {
                presence = nextPresence
            }
        } else {
            presence = nextPresence
        }
        if persistCache { saveCache(full, for: repository) }

        let newTop = (staggerNew && (!events.isEmpty || animateFromEmpty))
            ? Array(full.prefix { !existing.contains($0.id) }) : []
        guard !newTop.isEmpty else { events = full; return }

        events = Array(full.dropFirst(newTop.count))   // the prior list, unchanged on screen
        // Reveal oldest-new first so the newest ends on top, each pushing the
        // stack down; the per-item delay makes the staggered cascade.
        for (i, ev) in newTop.reversed().enumerated() {
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: UInt64(Double(i) * 0.16 * 1_000_000_000))
                withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) {
                    events.insert(ev, at: 0)
                }
            }
        }
    }

    static func discoverCachedPeople() {
        guard let data = try? Data(contentsOf: cacheFile),
              let byRepository = try? decoderDate.decode(
                [String: [FeedEvent]].self,
                from: data
              ) else { return }
        discoverPeople(in: byRepository.values.flatMap { $0 })
    }

    private static func discoverPeople(in events: [FeedEvent]) {
        var identities: [String: (login: String, avatarURL: String?)] = [:]
        for event in events {
            let key = event.actor.lowercased()
            let existingAvatar = identities[key]?.avatarURL
            identities[key] = (event.actor, event.avatarURL ?? existingAvatar)
        }
        PersonProfileManager.shared.discover(identities.values.map {
            (login: $0.login, githubFullName: nil, avatarURL: $0.avatarURL)
        })
    }

    // MARK: parsing

    private func date(_ any: Any?) -> Date? {
        guard let s = any as? String else { return nil }
        return isoFull.date(from: s)
    }

    private func parse(_ e: [String: Any]) -> FeedEvent? {
        let actorObj = e["actor"] as? [String: Any]
        guard let id = e["id"] as? String,
              let type = e["type"] as? String,
              let actor = actorObj?["login"] as? String,
              let when = date(e["created_at"]) else { return nil }
        let avatar = actorObj?["avatar_url"] as? String
        let payload = e["payload"] as? [String: Any] ?? [:]

        func pr() -> [String: Any]? { payload["pull_request"] as? [String: Any] }

        let kind: FeedKind?
        switch type {
        case "PushEvent":
            let ref = (payload["ref"] as? String ?? "").replacingOccurrences(of: "refs/heads/", with: "")
            let commits = (payload["commits"] as? [[String: Any]] ?? []).map {
                FeedKind.Commit(sha: String(($0["sha"] as? String ?? "").prefix(7)),
                                message: ($0["message"] as? String ?? "").split(separator: "\n").first.map(String.init) ?? "")
            }
            // This events API strips `size`/`commits`, so we derive the count from
            // the before...head range via the compare API (fetched + cached below).
            guard !ref.isEmpty else { kind = nil; break }
            let before = payload["before"] as? String ?? ""
            let head = payload["head"] as? String ?? ""
            if !before.isEmpty, !head.isEmpty, before.contains(where: { $0 != "0" }) {
                pushSHAs[id] = (before, head)
            }
            kind = .push(branch: ref, count: commitCounts["\(before)...\(head)"], commits: commits)
        case "PullRequestEvent":
            let action = payload["action"] as? String ?? ""
            guard let p = pr(), let num = p["number"] as? Int else { kind = nil; break }
            let title = p["title"] as? String ?? ""
            let head = ((p["head"] as? [String: Any])?["ref"] as? String) ?? ""
            let merged = p["merged"] as? Bool ?? false
            // This events API uses action "merged"; the classic shape is
            // "closed" + merged=true. Handle both.
            if action == "merged" || (action == "closed" && merged) {
                let base = ((p["base"] as? [String: Any])?["ref"] as? String) ?? "main"
                kind = .prMerged(number: num, title: title, base: base, branch: head,
                                 additions: p["additions"] as? Int, deletions: p["deletions"] as? Int,
                                 commits: nil, duration: nil)
            } else if action == "opened" || action == "reopened" {
                kind = .prOpened(number: num, title: title, branch: head)
            } else { kind = nil }
        case "CreateEvent":
            if (payload["ref_type"] as? String) == "branch", let ref = payload["ref"] as? String {
                kind = .branchCreated(ref)
            } else { kind = nil }
        case "DeleteEvent":
            if (payload["ref_type"] as? String) == "branch", let ref = payload["ref"] as? String {
                kind = .branchDeleted(ref)
            } else { kind = nil }
        case "PullRequestReviewEvent":
            guard let p = pr(), let num = p["number"] as? Int else { kind = nil; break }
            kind = .review(number: num, title: p["title"] as? String ?? "",
                           state: (payload["review"] as? [String: Any])?["state"] as? String ?? "")
        case "IssuesEvent":
            let action = payload["action"] as? String ?? ""
            guard let issue = payload["issue"] as? [String: Any], let num = issue["number"] as? Int else { kind = nil; break }
            let title = issue["title"] as? String ?? ""
            if action == "opened" || action == "reopened" { kind = .issueOpened(number: num, title: title) }
            else if action == "closed" { kind = .issueClosed(number: num, title: title) }
            else { kind = nil }
        default:
            kind = nil
        }
        guard let kind else { return nil }
        return FeedEvent(id: id, actor: actor, avatarURL: avatar, date: when, kind: kind)
    }

    private func computePresence(from events: [FeedEvent]) -> [Presence] {
        let now = Date()
        let window = TimeInterval(max(1, UserDefaults.standard.integer(forKey: SettingsKey.officeHours))) * 3600
        let visible = Self.filterNoise(events)
        let threshold = max(2, UserDefaults.standard.integer(forKey: SettingsKey.fireThreshold))
        let byActor = Dictionary(grouping: visible, by: \.actor)
        return byActor.map { login, evs in
            let last = evs.map(\.date).max() ?? .distantPast
            let recent = evs.filter { now.timeIntervalSince($0.date) <= idleThreshold }.count
            return Presence(login: login, avatarURL: evs.first?.avatarURL, lastActive: last,
                            recentCount: recent, idle: now.timeIntervalSince(last) > idleThreshold)
        }
        .filter { now.timeIntervalSince($0.lastActive) < window }   // within the configured window
        // "On fire" (>= threshold events / 30m) first, then most-recently-active.
        .sorted { a, b in
            let aFire = a.recentCount >= threshold, bFire = b.recentCount >= threshold
            if aFire != bFire { return aFire }
            return a.lastActive > b.lastActive
        }
    }
}

// MARK: - gh CLI bridge

enum GH {
    /// Resolved path to the `gh` binary (the app's PATH may not include Homebrew).
    static let path: String = {
        for p in ["/opt/homebrew/bin/gh", "/usr/local/bin/gh", NSHomeDirectory() + "/.local/bin/gh"]
        where FileManager.default.isExecutableFile(atPath: p) { return p }
        return "/usr/bin/env"   // fallback; args get "gh" prepended below
    }()

    static func api(
        _ apiPath: String,
        cacheFor: TimeInterval = 0
    ) async -> Data? {
        await query(["api", apiPath], cacheFor: cacheFor)
    }

    /// The signed-in GitHub login, or nil when `gh` is unavailable. Cached for an
    /// hour by the broker, since it only changes when the user re-authenticates.
    static func viewerLogin() async -> String? {
        guard let data = await api("user", cacheFor: 3_600),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let login = json["login"] as? String,
              !login.isEmpty else { return nil }
        return login
    }

    /// Coalesces identical reads across tabs and windows, keeps short-lived
    /// responses in memory, and backs off repeated failures for the same query.
    static func query(
        _ args: [String],
        cacheFor: TimeInterval = 0
    ) async -> Data? {
        await GHRequestBroker.shared.query(args, cacheFor: cacheFor)
    }

    /// Run `gh <args>` off the main thread and return stdout data (nil on failure).
    static func run(_ args: [String]) async -> Data? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: path)
                process.arguments = (path == "/usr/bin/env" ? ["gh"] : []) + args
                let out = Pipe()
                process.standardOutput = out
                process.standardError = Pipe()
                do { try process.run() } catch { continuation.resume(returning: nil); return }
                let data = out.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                continuation.resume(returning: process.terminationStatus == 0 ? data : nil)
            }
        }
    }
}

private actor GHRequestBroker {
    static let shared = GHRequestBroker()

    private struct CachedResponse {
        let data: Data
        let expiresAt: Date
    }

    private struct FailureState {
        let attempts: Int
        let retryAt: Date
    }

    private var inFlight: [String: Task<Data?, Never>] = [:]
    private var cache: [String: CachedResponse] = [:]
    private var failures: [String: FailureState] = [:]

    func query(_ arguments: [String], cacheFor: TimeInterval) async -> Data? {
        let key = arguments.joined(separator: "\u{1F}")
        let now = Date()

        if let cached = cache[key], cached.expiresAt > now {
            return cached.data
        }
        cache[key] = nil

        if let failure = failures[key], failure.retryAt > now {
            return nil
        }
        if let task = inFlight[key] {
            return await task.value
        }

        let task = Task<Data?, Never> {
            await GHConcurrencyLimiter.shared.run(arguments)
        }
        inFlight[key] = task
        let result = await task.value
        inFlight[key] = nil

        if let result {
            failures[key] = nil
            if cacheFor > 0 {
                cache[key] = CachedResponse(
                    data: result,
                    expiresAt: now.addingTimeInterval(cacheFor)
                )
            }
        } else {
            let attempts = min((failures[key]?.attempts ?? 0) + 1, 8)
            let delay = min(300, pow(2, Double(attempts - 1)) * 5)
            failures[key] = FailureState(
                attempts: attempts,
                retryAt: now.addingTimeInterval(delay)
            )
        }
        return result
    }
}

private actor GHConcurrencyLimiter {
    static let shared = GHConcurrencyLimiter()

    private let maximumConcurrentReads = 4
    private var activeReads = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func run(_ arguments: [String]) async -> Data? {
        await acquire()
        let result = await GH.run(arguments)
        release()
        return result
    }

    private func acquire() async {
        if activeReads < maximumConcurrentReads {
            activeReads += 1
            return
        }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    private func release() {
        if waiters.isEmpty {
            activeReads = max(0, activeReads - 1)
        } else {
            waiters.removeFirst().resume()
        }
    }
}
