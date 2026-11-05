import Foundation

/// Issue text an agent has just written, shown before GitHub says so.
///
/// A pilot ticking its checklist edits the issue on GitHub, and the board
/// only saw it once the next fetch came back, which with GitHub's own lag
/// and the fetch cache was ten seconds or more: long enough to look like
/// the edit had failed. Now whatever writes an issue body through `runway`
/// drops the new text here first, and the board shows it within a second.
/// The real fetch takes over once it carries the same text, or after a few
/// minutes if it never does (the edit failed, or GitHub reworded it).
@MainActor
final class PendingBodies {
    static let shared = PendingBodies()

    private static let lifetime: TimeInterval = 180

    private struct Entry {
        let body: String
        let at: Date
    }

    private var entries: [String: Entry] = [:]

    static var folder: URL {
        RunwayStorage.supportDir.appendingPathComponent("pending-bodies", isDirectory: true)
    }

    private static func key(_ repository: String, _ number: Int) -> String {
        "\(repository.lowercased().replacingOccurrences(of: "/", with: "__"))__\(number)"
    }

    /// Reread what changed. Each file's own date is checked, not the
    /// folder's: rewriting a file in place leaves the folder's date alone,
    /// so a second edit to the same issue kept showing the first one's text,
    /// over the top of GitHub's newer answer.
    func reload() {
        let manager = FileManager.default
        let files = (try? manager.contentsOfDirectory(
            at: Self.folder,
            includingPropertiesForKeys: [.contentModificationDateKey]
        )) ?? []
        var next: [String: Entry] = [:]
        for file in files where file.pathExtension == "md" {
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
            guard let body = try? String(contentsOf: file, encoding: .utf8) else { continue }
            next[key] = Entry(body: body, at: at)
        }
        entries = next
    }

    /// The written text for each issue of this repository still waiting on
    /// GitHub.
    func bodies(in repository: String) -> [Int: (body: String, at: Date)] {
        let prefix = Self.key(repository, 0).dropLast(1)
        var found: [Int: (body: String, at: Date)] = [:]
        for (key, entry) in entries where key.hasPrefix(prefix) {
            if let number = Int(key.dropFirst(prefix.count)) { found[number] = (entry.body, entry.at) }
        }
        return found
    }

    /// GitHub has caught up with this one.
    func settle(_ repository: String, _ number: Int) {
        let key = Self.key(repository, number)
        entries.removeValue(forKey: key)
        try? FileManager.default.removeItem(at: Self.folder.appendingPathComponent("\(key).md"))
    }

    static func same(_ a: String, _ b: String) -> Bool {
        func plain(_ text: String) -> String {
            text.replacingOccurrences(of: "\r\n", with: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return plain(a) == plain(b)
    }
}
