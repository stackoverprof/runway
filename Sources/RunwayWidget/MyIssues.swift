import Foundation

/// The open issues assigned to me across VISKA-IO, with the Priority set on
/// "Erbin's Board" (project #72).
struct AssignedIssue: Identifiable, Equatable {
    let number: Int
    let title: String
    let repository: String
    let url: URL
    let body: String
    let cluster: String?
    let priority: String?
    let updatedAt: Date
    /// Only open issues are listed; kept for the shared status code.
    var isClosed: Bool { false }
    var isFlight: Bool { false }
    var legs: [Int] { [] }
    var landedLegs: Int { 0 }

    var id: String { "\(repository)#\(number)" }
    var shortRepository: String { repository.components(separatedBy: "/").last ?? repository }
}

@MainActor @Observable final class AssignedIssues {
    static let shared = AssignedIssues()

    private(set) var issues: [AssignedIssue] = []
    private(set) var loading = false
    private(set) var didLoad = false
    private(set) var error: String?
    /// My open PRs anywhere in the org, by the issues their body mentions
    /// ("Part of #14892", "VISKA-IO/monorepo#14893"), keyed by issue id.
    private(set) var mentionedPulls: [String: [LinkedPull]] = [:]
    @ObservationIgnored private var pollTask: Task<Void, Never>?

    static let owner = "VISKA-IO"
    static let clusterColor = "5319e7"

    func startPolling(every seconds: UInt64 = 120) {
        guard pollTask == nil else { return }
        pollTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                // Retry soon while nothing has loaded yet.
                let wait = self?.didLoad == true ? seconds : 10
                try? await Task.sleep(nanoseconds: wait * 1_000_000_000)
            }
        }
    }

    func refresh() async {
        guard !loading else { return }
        loading = true
        defer { loading = false }
        async let searched = Self.searchAssigned()
        async let mentions = Self.myPullMentions()
        guard let found = await searched else {
            if !didLoad { error = GitHubFeed.ghHint }
            return
        }
        issues = found.map { issue in
            AssignedIssue(
                number: issue.number, title: issue.title, repository: issue.repository,
                url: issue.url, body: issue.body, cluster: issue.cluster,
                priority: issue.priority,
                updatedAt: issue.updatedAt
            )
        }
        if let found = await mentions { mentionedPulls = found }
        error = nil
        didLoad = true
    }

    private static let reference = try! NSRegularExpression(
        pattern: #"(?:([A-Za-z0-9-]+)/([A-Za-z0-9._-]+))?#(\d+)"#)

    private static func myPullMentions() async -> [String: [LinkedPull]]? {
        guard let data = await GH.run([
            "search", "prs", "--author", "@me", "--state", "open", "--owner", owner,
            "--limit", "200", "--json", "number,title,url,repository,isDraft,body",
        ]),
            let rows = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else { return nil }
        var result: [String: [LinkedPull]] = [:]
        for row in rows {
            guard let number = row["number"] as? Int, let title = row["title"] as? String,
                  let link = row["url"] as? String, let url = URL(string: link) else { continue }
            let repository = (row["repository"] as? [String: Any])?["nameWithOwner"] as? String ?? ""
            let body = row["body"] as? String ?? ""
            let pull = LinkedPull(number: number, title: title, url: url, repository: repository,
                                  isDraft: row["isDraft"] as? Bool ?? false, branch: nil)
            var ids = Set<String>()
            let range = NSRange(body.startIndex..., in: body)
            for match in reference.matches(in: body, range: range) {
                guard let n = Range(match.range(at: 3), in: body).map({ String(body[$0]) }) else { continue }
                var repo = repository
                if let o = Range(match.range(at: 1), in: body), let r = Range(match.range(at: 2), in: body) {
                    repo = "\(body[o])/\(body[r])"
                }
                ids.insert("\(repo)#\(n)")
            }
            for id in ids { result[id, default: []].append(pull) }
        }
        return result
    }

    /// P1 first, then P2…P5, then no priority; newest activity first within each.
    var grouped: [(priority: String, issues: [AssignedIssue])] {
        let order = ["P1", "P2", "P3", "P4", "P5", "No priority"]
        let groups = Dictionary(grouping: issues) { $0.priority ?? "No priority" }
        return order.compactMap { key in
            guard let list = groups[key], !list.isEmpty else { return nil }
            return (key, list.sorted { $0.updatedAt > $1.updatedAt })
        }
    }

    private struct Found {
        let number: Int, title: String, repository: String, url: URL, body: String, cluster: String?, priority: String?, updatedAt: Date
    }

    private static func searchAssigned() async -> [Found]? {
        guard let data = await GH.run([
            "search", "issues", "--assignee", "@me", "--state", "open", "--owner", owner,
            "--limit", "200", "--json", "number,title,repository,url,labels,updatedAt,body",
        ]),
            let rows = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else { return nil }
        let iso = ISO8601DateFormatter()
        return rows.compactMap { row in
            guard let number = row["number"] as? Int,
                  let title = row["title"] as? String,
                  let link = row["url"] as? String, let url = URL(string: link)
            else { return nil }
            let repository = (row["repository"] as? [String: Any])?["nameWithOwner"] as? String ?? ""
            let labels = row["labels"] as? [[String: Any]] ?? []
            let names = labels.compactMap { $0["name"] as? String }
            // The mission is the title's prefix ("Pricing: …") when a label of that name is on the issue; older
            // issues fall back to the cluster label colour.
            let prefix = title.range(of: ": ").map { String(title[..<$0.lowerBound]) }
            let cluster = prefix.flatMap { names.contains($0) ? $0 : nil }
                ?? labels.first { ($0["color"] as? String)?.lowercased() == clusterColor }?["name"] as? String
            // Priority is the issue's one P1–P5 label (the Team Board was retired on 19 Nov 2026).
            let priority = names.first { $0.range(of: "^P[1-5]$", options: .regularExpression) != nil }
            let updated = (row["updatedAt"] as? String).flatMap(iso.date(from:)) ?? .distantPast
            return Found(number: number, title: title, repository: repository, url: url, body: row["body"] as? String ?? "", cluster: cluster, priority: priority, updatedAt: updated)
        }
    }

}

/// An open PR shown under an issue: from the Pulls data (its branch ends
/// with the issue's number) or from my PRs whose body mentions the issue.
struct LinkedPull: Identifiable, Equatable, Sendable {
    let number: Int
    let title: String
    let url: URL
    let repository: String
    let isDraft: Bool
    /// Known for PRs in the Pulls repository; nil for the rest.
    let branch: String?
    var id: String { url.absoluteString }
}

/// CI state of the open PRs shown under my issues, by PR URL: SUCCESS,
/// FAILURE, ERROR, PENDING, EXPECTED, or NONE when the PR has no checks.
@MainActor @Observable final class PullChecks {
    static let shared = PullChecks()
    private(set) var states: [String: String] = [:]
    @ObservationIgnored private var running = false

    func refresh(_ urls: [URL]) async {
        guard !running, !urls.isEmpty else { return }
        running = true
        defer { running = false }
        var next = states
        let unique = Array(Set(urls))
        for start in stride(from: 0, to: unique.count, by: 40) {
            let batch = Array(unique[start..<min(start + 40, unique.count)])
            let fields = batch.enumerated().map { index, url in
                "p\(index): resource(url: \"\(url.absoluteString)\") { ... on PullRequest { url commits(last: 1) { nodes { commit { statusCheckRollup { state } } } } } }"
            }.joined(separator: "\n")
            guard let data = await GH.run(["api", "graphql", "-f", "query={\(fields)}"]),
                  let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let nodes = root["data"] as? [String: Any] else { continue }
            for case let node as [String: Any] in nodes.values {
                guard let url = node["url"] as? String else { continue }
                let commit = ((node["commits"] as? [String: Any])?["nodes"] as? [[String: Any]])?.first?["commit"] as? [String: Any]
                let state = (commit?["statusCheckRollup"] as? [String: Any])?["state"] as? String
                next[url] = state ?? "NONE"
            }
        }
        states = next
    }
}
