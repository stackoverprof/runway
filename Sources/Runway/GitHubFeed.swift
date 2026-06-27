import SwiftUI
import Foundation

// MARK: - Models

enum FeedKind: Codable {
    case push(branch: String, count: Int?, commits: [Commit])
    case prOpened(number: Int, title: String, branch: String)
    case prMerged(number: Int, title: String, base: String, branch: String, additions: Int?, deletions: Int?)
    case branchCreated(String)
    case branchDeleted(String)
    case review(number: Int, title: String, state: String)
    case issueOpened(number: Int, title: String)
    case issueClosed(number: Int, title: String)

    struct Commit: Identifiable, Codable {
        let id = UUID(); let sha: String; let message: String
        enum CodingKeys: String, CodingKey { case sha, message }   // id is regenerated
    }
}

struct FeedEvent: Identifiable, Codable {
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
    private var offline = false   // for the offline/online toast transition
    /// Commit counts for pushes (this events API strips `size`), keyed by
    /// "before...head" and fetched via the compare API, with an in-flight guard.
    private var commitCounts: [String: Int] = [:]
    private var pushSHAs: [String: (before: String, head: String)] = [:]
    private var fetchingCounts: Set<String> = []

    /// User-facing hint shown when `gh` can't be reached (missing or not signed in).
    static let ghHint = "Can't reach GitHub. Make sure the GitHub CLI is installed and you're signed in: run `gh auth login` in a terminal."

    /// Seconds between automatic polls (Settings, default 45).
    var pollInterval: UInt64 { UInt64(max(5, UserDefaults.standard.integer(forKey: SettingsKey.pollInterval))) }
    /// How long without activity counts as idle (Settings, default 30 min).
    private var idleThreshold: TimeInterval { TimeInterval(max(1, UserDefaults.standard.integer(forKey: SettingsKey.idleMinutes)) * 60) }
    private let isoFull = ISO8601DateFormatter()

    // Disk cache so reopening the app shows the last feed instantly (no skeleton).
    private static var cacheFile: URL { AgentControl.supportDir.appendingPathComponent("feed-cache.json") }
    private static let coderDate: JSONEncoder = { let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; return e }()
    private static let decoderDate: JSONDecoder = { let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d }()

    init() { loadCache() }

    /// Load the cached feed for the current repo (if any) so the left pane renders
    /// immediately instead of a skeleton. Recomputes presence from it.
    private func loadCache() {
        didLoad = false; events = []; presence = []
        guard let data = try? Data(contentsOf: Self.cacheFile),
              let byRepo = try? Self.decoderDate.decode([String: [FeedEvent]].self, from: data),
              let cached = byRepo[repo], !cached.isEmpty else { return }
        events = cached.sorted { $0.date > $1.date }
        presence = computePresence(from: events)
        didLoad = true
    }

    /// Delete the on-disk feed cache and refetch the current repo.
    static func clearCache() {
        try? FileManager.default.removeItem(at: cacheFile)
        shared.events = []; shared.presence = []; shared.didLoad = false
        Task { await shared.refresh() }
    }

    /// Inject synthetic feed events for local testing. This does not touch the
    /// on-disk cache, so a real poll will replace the mock data.
    func injectSyntheticEvents() {
        guard !repo.isEmpty else { return }
        let count = Int.random(in: 1...3)
        let incoming = (0..<count).map { index in makeSyntheticEvent(offset: index) }
        merge(incoming, staggerNew: true, persistCache: false, animateFromEmpty: true)
        lastError = nil
        didLoad = true
    }

    private func saveCache(_ list: [FeedEvent]) {
        guard !repo.isEmpty else { return }
        var byRepo = (try? Data(contentsOf: Self.cacheFile))
            .flatMap { try? Self.decoderDate.decode([String: [FeedEvent]].self, from: $0) } ?? [:]
        byRepo[repo] = Array(list.prefix(200))   // cap per repo
        if let data = try? Self.coderDate.encode(byRepo) { try? data.write(to: Self.cacheFile) }
    }

    func startPolling() {
        fetchRepoList()
        Task { @MainActor in
            while !Task.isCancelled {
                if repo.isEmpty { fetchRepoList() }   // keep retrying to bootstrap (e.g. after gh login)
                await refresh()
                try? await Task.sleep(nanoseconds: pollInterval * 1_000_000_000)
            }
        }
    }

    func setRepo(_ r: String) {
        guard r != repo, !r.isEmpty else { return }
        repo = r
        UserDefaults.standard.set(r, forKey: "runway.repo")
        presence = []; lastError = nil; loadedPages = 1; canLoadMore = true
        loadCache()   // show this repo's cached feed instantly (or skeleton if none)
        Task { await refresh() }
    }

    /// Populate the repo switcher with every repo the signed-in user can reach
    /// (their own *and* their orgs'), most-recently-pushed first. Nothing
    /// org-specific is hardcoded; the picker also accepts a free-form `owner/repo`.
    func fetchRepoList() {
        Task { @MainActor in
            guard let data = await GH.run(["api",
                "/user/repos?per_page=100&sort=pushed&affiliation=owner,organization_member,collaborator",
                "-q", ".[].full_name"]),
                  let s = String(data: data, encoding: .utf8) else {
                if repo.isEmpty { lastError = Self.ghHint }
                return
            }
            let repos = s.split(whereSeparator: \.isNewline).map(String.init)
            var seen = Set<String>(); var ordered: [String] = []
            for r in ([repo] + repos) where !r.isEmpty && seen.insert(r).inserted { ordered.append(r) }
            if !ordered.isEmpty {
                availableRepos = ordered
                if repo.isEmpty, let first = ordered.first { setRepo(first) }   // first run: show something
            } else if repo.isEmpty {
                lastError = Self.ghHint
            }
        }
    }

    func refresh() async {
        guard !repo.isEmpty else { return }
        loading = events.isEmpty
        guard let page = await fetchPage(1) else {
            if !offline {
                offline = true
                ToastCenter.shared.show("Can't reach GitHub", icon: "wifi.slash",
                                        tint: Color(red: 0.95, green: 0.45, blue: 0.40))
            }
            lastError = Self.ghHint; loading = false; return
        }
        if offline {
            offline = false
            ToastCenter.shared.show("Back online", icon: "wifi",
                                    tint: Color(red: 0.30, green: 0.78, blue: 0.45))
        }
        merge(page.events, staggerNew: true)
        fetchCommitCounts()
        lastError = nil
        didLoad = true
        loading = false
    }

    /// Load the next page of older events (infinite scroll). The events API is
    /// capped at ~300 events, so this naturally stops when GitHub runs out.
    func loadMore() async {
        guard didLoad, canLoadMore, !loadingMore, !repo.isEmpty else { return }
        loadingMore = true
        defer { loadingMore = false }
        let next = loadedPages + 1
        guard let page = await fetchPage(next), !page.events.isEmpty else {
            canLoadMore = false; return
        }
        merge(page.events)
        loadedPages = next
        canLoadMore = page.full
        fetchCommitCounts()
    }

    /// Fill in commit counts for pushes that don't have one yet, via the compare
    /// API (cached by range + an in-flight set so each range is fetched once).
    private func fetchCommitCounts() {
        for e in events {
            guard case let .push(_, count, _) = e.kind, count == nil,
                  let shas = pushSHAs[e.id] else { continue }
            let key = "\(shas.before)...\(shas.head)"
            if let cached = commitCounts[key] { applyCount(cached, to: e.id); continue }
            if fetchingCounts.contains(key) { continue }
            fetchingCounts.insert(key)
            Task { @MainActor in
                defer { fetchingCounts.remove(key) }
                guard let data = await GH.api("/repos/\(repo)/compare/\(key)"),
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let total = json["total_commits"] as? Int else { return }
                commitCounts[key] = total
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

    private func fetchPage(_ page: Int) async -> (events: [FeedEvent], full: Bool)? {
        guard let data = await GH.api("/repos/\(repo)/events?per_page=100&page=\(page)"),
              let raw = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return nil }
        let hideBots = UserDefaults.standard.bool(forKey: SettingsKey.hideBots)
        let parsed = raw.compactMap(parse).filter { !(hideBots && $0.actor.hasSuffix("[bot]")) }
        return (parsed, raw.count >= 100)
    }

    /// Merge new events (deduped by id, newest first), recompute presence, cache.
    /// With `staggerNew`, brand-new events at the top reveal one-by-one (phone-
    /// notification style): older cards slide down as each new one fades in.
    private func merge(_ incoming: [FeedEvent], staggerNew: Bool = false, persistCache: Bool = true, animateFromEmpty: Bool = false) {
        let existing = Set(events.map(\.id))
        var byID = [String: FeedEvent](minimumCapacity: events.count + incoming.count)
        for e in events { byID[e.id] = e }
        for e in incoming { byID[e.id] = e }
        let full = byID.values.sorted { $0.date > $1.date }
        let hadEvents = !events.isEmpty

        let nextPresence = computePresence(from: full)
        if hadEvents || animateFromEmpty {
            withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) {
                presence = nextPresence
            }
        } else {
            presence = nextPresence
        }
        if persistCache { saveCache(full) }

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

    private func makeSyntheticEvent(offset: Int) -> FeedEvent {
        let samples: [(actor: String, avatarURL: String?, kind: FeedKind)] = [
            ("alex", nil, .push(
                branch: "feature/live-feed-\(Int.random(in: 12...98))",
                count: Int.random(in: 1...4),
                commits: [
                    .init(sha: randomSHA(), message: randomCommitMessage()),
                    .init(sha: randomSHA(), message: randomCommitMessage())
                ]
            )),
            ("maria", nil, .prOpened(
                number: Int.random(in: 180...999),
                title: randomPRTitle(),
                branch: "feature/\(randomSlug())"
            )),
            ("sam", nil, .issueOpened(
                number: Int.random(in: 120...899),
                title: randomIssueTitle()
            )),
            ("devon", nil, .branchCreated("wip/\(randomSlug())")),
            ("jordan", nil, .review(
                number: Int.random(in: 180...999),
                title: randomPRTitle(),
                state: ["APPROVED", "CHANGES_REQUESTED", "COMMENTED"].randomElement() ?? "COMMENTED"
            )),
            ("taylor", nil, .prMerged(
                number: Int.random(in: 180...999),
                title: randomPRTitle(),
                base: ["main", "develop", "release"].randomElement() ?? "main",
                branch: "feature/\(randomSlug())",
                additions: Int.random(in: 5...240),
                deletions: Int.random(in: 0...180)
            )),
            ("casey", nil, .issueClosed(
                number: Int.random(in: 120...899),
                title: randomIssueTitle()
            )),
            ("rowan", nil, .branchDeleted("old/\(randomSlug())"))
        ]
        let sample = samples.randomElement()!
        return FeedEvent(
            id: "synthetic-\(Date().timeIntervalSince1970)-\(offset)-\(UUID().uuidString)",
            actor: sample.actor,
            avatarURL: sample.avatarURL,
            date: Date().addingTimeInterval(-Double(offset) * 45),
            kind: sample.kind
        )
    }

    private func randomSlug() -> String {
        ["alpha", "beta", "gamma", "delta", "ember", "flux", "orbit", "pulse", "quartz", "signal"].randomElement()! + "-\(Int.random(in: 10...99))"
    }

    private func randomSHA() -> String {
        let digits = Array("0123456789abcdef")
        return String((0..<7).map { _ in digits.randomElement()! })
    }

    private func randomCommitMessage() -> String {
        [
            "Tighten feed animation timing",
            "Polish row entrance transitions",
            "Refine feed preview spacing",
            "Adjust timeline card layout",
            "Make the feed feel more alive",
            "Fix the insert cascade"
        ].randomElement()!
    }

    private func randomPRTitle() -> String {
        [
            "Improve feed motion",
            "Ship the timeline polish",
            "Smooth the incoming card cascade",
            "Reduce visual jump on refresh",
            "Tune feed reveal timing"
        ].randomElement()!
    }

    private func randomIssueTitle() -> String {
        [
            "Feed rows should animate when new data lands",
            "Timeline reveal needs a clearer cue",
            "Add a quick way to simulate incoming events",
            "Test the activity pane with synthetic data"
        ].randomElement()!
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
                                 additions: p["additions"] as? Int, deletions: p["deletions"] as? Int)
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
        let byActor = Dictionary(grouping: events, by: \.actor)
        return byActor.map { login, evs in
            let last = evs.map(\.date).max() ?? .distantPast
            let recent = evs.filter { now.timeIntervalSince($0.date) <= idleThreshold }.count
            return Presence(login: login, avatarURL: evs.first?.avatarURL, lastActive: last,
                            recentCount: recent, idle: now.timeIntervalSince(last) > idleThreshold)
        }
        .filter { now.timeIntervalSince($0.lastActive) < window }   // within the configured window
        // "On fire" (>= 5 events / 30m) first, then most-recently-active.
        .sorted { a, b in
            let aFire = a.recentCount >= 5, bFire = b.recentCount >= 5
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

    static func api(_ apiPath: String) async -> Data? { await run(["api", apiPath]) }

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
