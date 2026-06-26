import SwiftUI
import Foundation

// MARK: - Models

enum FeedKind {
    case push(branch: String, commits: [Commit])
    case prOpened(number: Int, title: String, branch: String)
    case prMerged(number: Int, title: String, base: String, branch: String, additions: Int?, deletions: Int?)
    case branchCreated(String)
    case review(number: Int, title: String, state: String)
    case issueOpened(number: Int, title: String)
    case issueClosed(number: Int, title: String)

    struct Commit: Identifiable { let id = UUID(); let sha: String; let message: String }
}

struct FeedEvent: Identifiable {
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

    /// Seconds between automatic polls.
    let pollInterval: UInt64 = 45
    private let idleThreshold: TimeInterval = 30 * 60
    private let isoFull = ISO8601DateFormatter()
    private init() {}

    func startPolling() {
        fetchRepoList()
        Task { @MainActor in
            while !Task.isCancelled {
                await refresh()
                try? await Task.sleep(nanoseconds: pollInterval * 1_000_000_000)
            }
        }
    }

    func setRepo(_ r: String) {
        guard r != repo, !r.isEmpty else { return }
        repo = r
        UserDefaults.standard.set(r, forKey: "runway.repo")
        events = []; presence = []; lastError = nil
        Task { await refresh() }
    }

    /// Populate the repo switcher. With no repo chosen yet, fall back to the
    /// authenticated user's own repos (via `gh`) — nothing org-specific is
    /// hardcoded, so it works for whoever is logged in.
    func fetchRepoList() {
        Task { @MainActor in
            var owner = repo.split(separator: "/").first.map(String.init) ?? ""
            if owner.isEmpty {
                if let data = await GH.run(["api", "user", "-q", ".login"]),
                   let login = String(data: data, encoding: .utf8)?
                       .trimmingCharacters(in: .whitespacesAndNewlines), !login.isEmpty {
                    owner = login
                }
            }
            guard !owner.isEmpty else { return }
            guard let data = await GH.run(["repo", "list", owner, "--limit", "50",
                                           "--json", "nameWithOwner", "-q", ".[].nameWithOwner"]),
                  let s = String(data: data, encoding: .utf8) else { return }
            let repos = s.split(whereSeparator: \.isNewline).map(String.init)
            var seen = Set<String>(); var ordered: [String] = []
            for r in ([repo] + repos) where !r.isEmpty && seen.insert(r).inserted { ordered.append(r) }
            if !ordered.isEmpty {
                availableRepos = ordered
                if repo.isEmpty { setRepo(ordered[0]) }   // first run: show something
            }
        }
    }

    func refresh() async {
        guard !repo.isEmpty else { return }
        loading = events.isEmpty
        guard let data = await GH.api("/repos/\(repo)/events?per_page=100") else {
            lastError = "gh unavailable"; loading = false; return
        }
        guard let raw = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            lastError = "parse error"; loading = false; return
        }
        let parsed = raw.compactMap(parse).filter { !$0.actor.hasSuffix("[bot]") }
        events = parsed
        presence = computePresence(from: parsed)
        lastError = nil
        loading = false
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
            kind = ref.isEmpty ? nil : .push(branch: ref, commits: commits)
        case "PullRequestEvent":
            let action = payload["action"] as? String ?? ""
            guard let p = pr(), let num = p["number"] as? Int else { kind = nil; break }
            let title = p["title"] as? String ?? ""
            let head = ((p["head"] as? [String: Any])?["ref"] as? String) ?? ""
            let merged = p["merged"] as? Bool ?? false
            if action == "closed", merged {
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
        let byActor = Dictionary(grouping: events, by: \.actor)
        return byActor.map { login, evs in
            let last = evs.map(\.date).max() ?? .distantPast
            let recent = evs.filter { now.timeIntervalSince($0.date) <= idleThreshold }.count
            return Presence(login: login, avatarURL: evs.first?.avatarURL, lastActive: last,
                            recentCount: recent, idle: now.timeIntervalSince(last) > idleThreshold)
        }
        .filter { now.timeIntervalSince($0.lastActive) < 6 * 3600 }   // shown if active in last 6h
        .sorted { $0.lastActive > $1.lastActive }
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
