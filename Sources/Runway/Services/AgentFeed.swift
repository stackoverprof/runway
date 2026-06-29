import SwiftUI
import Foundation

// MARK: - Models

struct AgentPost: Identifiable, Codable, Equatable {
    let id: String
    let author: String
    let title: String?
    let body: String
    let date: Date
}

/// A unified timeline entry: GitHub events and local agent posts, sorted by date.
enum TimelineEntry: Identifiable {
    case github(FeedEvent)
    case agent(AgentPost)

    var id: String {
        switch self {
        case let .github(e): return "gh-\(e.id)"
        case let .agent(p): return "agent-\(p.id)"
        }
    }

    var date: Date {
        switch self {
        case let .github(e): return e.date
        case let .agent(p): return p.date
        }
    }
}

// MARK: - Feed (agents append JSON lines to `$RUNWAY_FEED`)

@MainActor @Observable final class AgentFeed {
    static let shared = AgentFeed()

    var posts: [AgentPost] = []

    static var inboxFile: URL { AgentControl.feedInbox }
    private static var postsFile: URL { AgentControl.feedDir.appendingPathComponent("posts.json") }

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .custom { decoder in
            let c = try decoder.singleValueContainer()
            let raw = try c.decode(String.self)
            let f = ISO8601DateFormatter()
            f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let d = f.date(from: raw) { return d }
            f.formatOptions = [.withInternetDateTime]
            if let d = f.date(from: raw) { return d }
            throw DecodingError.dataCorruptedError(in: c, debugDescription: "bad date")
        }
        return d
    }()

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()

    init() { loadPosts() }

    /// Filter out merge noise: branch deletions and automated merge-commit pushes.
    /// Shared between timeline display and presence computation.
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
                // A push to the merge target branch within 2 min of a merge
                // event is the automated merge-commit push — hide it.
                let dominated = mergeTargets.contains { target in
                    target.branch == branch &&
                    abs(target.date.timeIntervalSince(event.date)) < 120
                }
                if dominated { return false }
                return true
            default:
                return true
            }
        }
    }

    /// Merge GitHub events with agent posts, newest first.
    func timeline(github events: [FeedEvent]) -> [TimelineEntry] {
        let filtered = Self.filterNoise(events)
        let gh = filtered.map { TimelineEntry.github($0) }
        let local = posts.map { TimelineEntry.agent($0) }
        return (gh + local).sorted { $0.date > $1.date }
    }

    func startWatching() {
        ensureInbox()
        Task { @MainActor in
            while !Task.isCancelled {
                pollInbox()
                try? await Task.sleep(nanoseconds: 400_000_000)
            }
        }
    }

    /// Inject a sample post for local testing.
    func injectSample() {
        let post = AgentPost(
            id: UUID().uuidString,
            author: "recap",
            title: "15-min recap",
            body: """
            ## Shipped
            - **Auth refactor** — migrated session handling to JWT
            - Fixed the *race condition* in `TokenStore.refresh()`
            - Closed PR `#1842` after review

            ### Blockers
            - CI flaky on `integration-tests` — investigating

            ```swift
            let feed = AgentFeed.shared
            feed.startWatching()
            ```

            **Status:** on track · *ETA Friday*
            """,
            date: Date()
        )
        append([post], animate: true)
    }

    /// Remove one local agent post and persist the updated list.
    func deletePost(id: String) {
        guard posts.contains(where: { $0.id == id }) else { return }
        let next = posts.filter { $0.id != id }
        withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) {
            posts = next
        }
        savePosts(next)
    }

    // MARK: Inbox

    private func ensureInbox() {
        let path = Self.inboxFile
        if !FileManager.default.fileExists(atPath: path.path) {
            FileManager.default.createFile(atPath: path.path, contents: nil)
        }
    }

    private func pollInbox() {
        guard let raw = try? String(contentsOf: Self.inboxFile, encoding: .utf8) else { return }
        let lines = raw.split(whereSeparator: \.isNewline).map(String.init)
        guard !lines.isEmpty else { return }

        var parsed: [AgentPost] = []
        var leftovers: [String] = []
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            if let post = decodeLine(trimmed) {
                parsed.append(post)
            } else {
                leftovers.append(trimmed)
            }
        }

        if !parsed.isEmpty {
            append(parsed, animate: true)
            let remainder = leftovers.joined(separator: "\n")
            try? remainder.data(using: .utf8)?.write(to: Self.inboxFile, options: .atomic)
        }
    }

    private func decodeLine(_ line: String) -> AgentPost? {
        guard let data = line.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }

        let body = unescape((json["body"] as? String) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return nil }

        let author = ((json["author"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines))
            .flatMap { $0.isEmpty ? nil : $0 } ?? "agent"
        let titleRaw = unescape((json["title"] as? String) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let id = (json["id"] as? String) ?? UUID().uuidString

        let date: Date
        if let s = json["date"] as? String {
            let f = ISO8601DateFormatter()
            f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            date = f.date(from: s) ?? ISO8601DateFormatter().date(from: s) ?? Date()
        } else {
            date = Date()
        }

        return AgentPost(id: id, author: author, title: titleRaw.isEmpty ? nil : titleRaw, body: body, date: date)
    }

    /// Turn shell-style `\\n` escapes into real newlines (common when agents post via CLI).
    private func unescape(_ s: String) -> String {
        s.replacingOccurrences(of: "\\n", with: "\n")
            .replacingOccurrences(of: "\\t", with: "\t")
            .replacingOccurrences(of: "\\r", with: "\r")
    }

    private func append(_ incoming: [AgentPost], animate: Bool) {
        var byID = [String: AgentPost](minimumCapacity: posts.count + incoming.count)
        for p in posts { byID[p.id] = p }
        for p in incoming { byID[p.id] = p }
        let merged = byID.values.sorted { $0.date > $1.date }
        let capped = Array(merged.prefix(200))
        if animate {
            withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) { posts = capped }
        } else {
            posts = capped
        }
        savePosts(capped)
    }

    private func loadPosts() {
        guard let data = try? Data(contentsOf: Self.postsFile),
              let list = try? Self.decoder.decode([AgentPost].self, from: data) else { return }
        posts = list.sorted { $0.date > $1.date }
    }

    private func savePosts(_ list: [AgentPost]) {
        guard let data = try? Self.encoder.encode(list) else { return }
        try? data.write(to: Self.postsFile, options: .atomic)
    }
}
