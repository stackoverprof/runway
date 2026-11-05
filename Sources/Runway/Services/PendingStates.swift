import Foundation

/// What a write just changed about an issue, other than its text, shown
/// before GitHub's reads catch up.
///
/// GitHub takes the write at once but its list and search answers lag it by
/// up to a minute, and the fetch is cached on top. So a flight a pilot had
/// just closed kept its teal for a minute, and a crew raised from a seat was
/// nowhere to be seen. Every `runway` verb that changes an issue now drops
/// what it changed here as well (open or closed, whose crew it is, which
/// crews a flight has and in what order, a brand new issue), and the board
/// shows it within a second. The text itself rides ``PendingBodies``.
///
/// An entry goes once a real fetch agrees with it, or after a few minutes
/// if one never does.
@MainActor
final class PendingStates {
    static let shared = PendingStates()

    private static let lifetime: TimeInterval = 300

    struct Leg: Codable, Equatable {
        let number: Int
        var title: String?
        var url: String?
    }

    struct Created: Codable, Equatable {
        let title: String
        let url: String
        var body: String?
    }

    struct Patch: Codable, Equatable {
        var state: String?
        var title: String?
        /// The flight it is a crew of; 0 when it was let go of one.
        var parent: Int?
        var addLegs: [Leg]?
        var removeLegs: [Int]?
        var legOrder: [Int]?
        var create: Created?
    }

    private struct Entry {
        let patch: Patch
        let at: Date
    }

    private var entries: [String: Entry] = [:]

    static var folder: URL {
        RunwayStorage.supportDir.appendingPathComponent("pending-states", isDirectory: true)
    }

    private static func key(_ repository: String, _ number: Int) -> String {
        "\(repository.lowercased().replacingOccurrences(of: "/", with: "__"))__\(number)"
    }

    /// Reread what changed, file by file, by each file's own date.
    func reload() {
        let manager = FileManager.default
        let files = (try? manager.contentsOfDirectory(
            at: Self.folder,
            includingPropertiesForKeys: [.contentModificationDateKey]
        )) ?? []
        var next: [String: Entry] = [:]
        for file in files where file.pathExtension == "json" {
            let key = file.deletingPathExtension().lastPathComponent
            let at = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate ?? .distantPast
            if Date().timeIntervalSince(at) > Self.lifetime {
                try? manager.removeItem(at: file)
                continue
            }
            if let kept = entries[key], kept.at == at {
                next[key] = kept
                continue
            }
            guard let data = try? Data(contentsOf: file),
                  let patch = try? JSONDecoder().decode(Patch.self, from: data) else { continue }
            next[key] = Entry(patch: patch, at: at)
        }
        entries = next
    }

    /// What is still waiting on GitHub, for each issue of this repository.
    func patches(in repository: String) -> [Int: (patch: Patch, at: Date)] {
        let prefix = Self.key(repository, 0).dropLast(1)
        var found: [Int: (patch: Patch, at: Date)] = [:]
        for (key, entry) in entries where key.hasPrefix(prefix) {
            if let number = Int(key.dropFirst(prefix.count)) { found[number] = (entry.patch, entry.at) }
        }
        return found
    }

    /// The app's own write, in the same file the CLI writes.
    func record(_ patch: Patch, repository: String, number: Int) {
        let manager = FileManager.default
        try? manager.createDirectory(at: Self.folder, withIntermediateDirectories: true)
        let file = Self.folder.appendingPathComponent("\(Self.key(repository, number)).json")
        var merged = (try? Data(contentsOf: file)).flatMap { try? JSONDecoder().decode(Patch.self, from: $0) } ?? Patch()
        if let state = patch.state { merged.state = state }
        if let title = patch.title { merged.title = title }
        if let parent = patch.parent { merged.parent = parent }
        if let order = patch.legOrder { merged.legOrder = order }
        if let create = patch.create { merged.create = create }
        if let add = patch.addLegs { merged.addLegs = (merged.addLegs ?? []) + add }
        if let remove = patch.removeLegs { merged.removeLegs = (merged.removeLegs ?? []) + remove }
        if let data = try? JSONEncoder().encode(merged) { try? data.write(to: file, options: .atomic) }
        reload()
    }

    /// GitHub has caught up with this one, or the write never happened.
    func settle(_ repository: String, _ number: Int) {
        let key = Self.key(repository, number)
        entries.removeValue(forKey: key)
        try? FileManager.default.removeItem(at: Self.folder.appendingPathComponent("\(key).json"))
    }

    /// Whether a fetched issue already says everything the patch says.
    static func agrees(_ issue: AssignedIssue, with patch: Patch) -> Bool {
        if let state = patch.state, issue.state != state { return false }
        if let title = patch.title, issue.title != title { return false }
        if let parent = patch.parent, issue.parent != (parent == 0 ? nil : parent) { return false }
        let legs = issue.legs.map(\.number)
        if let add = patch.addLegs, add.contains(where: { !legs.contains($0.number) }) { return false }
        if let remove = patch.removeLegs, remove.contains(where: legs.contains) { return false }
        if let order = patch.legOrder, legs.filter(order.contains) != order.filter(legs.contains) { return false }
        return true
    }

    /// The patch laid over an issue. Returns nil when nothing changes.
    static func apply(_ patch: Patch, at: Date, to issue: AssignedIssue, lookup: (Int) -> AssignedIssue?) -> AssignedIssue? {
        var next = issue
        if let state = patch.state, next.state != state {
            next.state = state
            next.closedAt = state == "CLOSED" ? (next.closedAt ?? at) : nil
        }
        if let title = patch.title { next.title = title }
        if let parent = patch.parent { next.parent = parent == 0 ? nil : parent }
        if let remove = patch.removeLegs { next.legs.removeAll { remove.contains($0.number) } }
        for leg in patch.addLegs ?? [] where !next.legs.contains(where: { $0.number == leg.number }) {
            let known = lookup(leg.number)
            guard let url = URL(string: leg.url ?? "") ?? known?.url else { continue }
            next.legs.append(IssueLeg(
                number: leg.number,
                title: leg.title ?? known?.title ?? "#\(leg.number)",
                state: known?.state ?? "OPEN",
                url: url,
                repository: nil
            ))
        }
        if let order = patch.legOrder {
            let named = order.compactMap { number in next.legs.first { $0.number == number } }
            let rest = next.legs.filter { !order.contains($0.number) }
            next.legs = named + rest
        }
        return next == issue ? nil : next
    }
}
