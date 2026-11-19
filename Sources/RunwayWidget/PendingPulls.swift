import Foundation

/// A pull request as a seat left it a moment ago, shown before GitHub's
/// lists catch up: retitled, made ready, merged, opened. The `gh` that seats
/// run (see ``AgentControl/ghShim``) reads the PR back straight after a write,
/// which is never stale, and drops it here. It goes once the real list holds
/// an edit at least as new, or after a few minutes.
@MainActor
final class PendingPulls {
    static let shared = PendingPulls()

    private static let lifetime: TimeInterval = 300

    private struct Entry {
        let pull: RepositoryPullRequest
        let at: Date
    }

    private var entries: [String: Entry] = [:]

    static var folder: URL {
        RunwayStorage.supportDir.appendingPathComponent("pending-pulls", isDirectory: true)
    }

    private static func key(_ repository: String, _ number: Int) -> String {
        "\(repository.lowercased().replacingOccurrences(of: "/", with: "__"))__\(number)"
    }

    func reload() {
        let manager = FileManager.default
        let files = (try? manager.contentsOfDirectory(
            at: Self.folder,
            includingPropertiesForKeys: [.contentModificationDateKey]
        )) ?? []
        guard !files.isEmpty || !entries.isEmpty else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
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
                  let pull = try? decoder.decode(RepositoryPullRequest.self, from: data) else { continue }
            next[key] = Entry(pull: pull, at: at)
        }
        entries = next
    }

    func pulls(in repository: String) -> [RepositoryPullRequest] {
        let prefix = Self.key(repository, 0).dropLast(1)
        return entries.filter { $0.key.hasPrefix(prefix) }.map(\.value.pull)
    }

    func settle(_ repository: String, _ number: Int) {
        let key = Self.key(repository, number)
        entries.removeValue(forKey: key)
        try? FileManager.default.removeItem(at: Self.folder.appendingPathComponent("\(key).json"))
    }
}
