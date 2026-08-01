import Foundation

struct LocalRepository: Equatable, Sendable {
    let nameWithOwner: String
    let path: String
}

enum LocalRepositoryDirectory {
    static func discoverOnDevice() -> [LocalRepository] {
        discover(in: NSHomeDirectory(), maximumDepth: 6)
    }

    static func discover(
        in rootPath: String,
        maximumDepth: Int? = nil
    ) -> [LocalRepository] {
        let root = (rootPath as NSString).expandingTildeInPath
        guard FileManager.default.fileExists(atPath: root) else { return [] }
        let checkouts = checkoutPaths(
            in: URL(fileURLWithPath: root, isDirectory: true),
            maximumDepth: maximumDepth
        )

        var byRepository: [String: LocalRepository] = [:]
        for checkout in checkouts {
            guard let remote = originURL(in: checkout),
                  let repository = parseGitHubRepository(from: remote) else { continue }
            let candidate = LocalRepository(nameWithOwner: repository, path: checkout)
            let key = repository.lowercased()
            if let existing = byRepository[key], !isPreferred(candidate.path, over: existing.path) {
                continue
            }
            byRepository[key] = candidate
        }

        return byRepository.values.sorted {
            $0.nameWithOwner.localizedCaseInsensitiveCompare($1.nameWithOwner) == .orderedAscending
        }
    }

    static func directCheckoutPath(
        for repository: String,
        homePath: String = NSHomeDirectory()
    ) -> String? {
        guard let repositoryName = repository.split(separator: "/").last else { return nil }
        let home = URL(fileURLWithPath: homePath, isDirectory: true)
        var candidates = [home.appendingPathComponent(String(repositoryName), isDirectory: true)]
        if let homeDirectories = try? FileManager.default.contentsOfDirectory(
            at: home,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) {
            candidates += homeDirectories.map {
                $0.appendingPathComponent(String(repositoryName), isDirectory: true)
            }
        }

        let key = repository.lowercased()
        return candidates.first { candidate in
            guard FileManager.default.fileExists(
                atPath: candidate.appendingPathComponent(".git").path
            ), let remote = originURL(in: candidate.path),
                  parseGitHubRepository(from: remote)?.lowercased() == key else {
                return false
            }
            return true
        }?.path
    }

    private static func checkoutPaths(
        in root: URL,
        maximumDepth: Int?
    ) -> [String] {
        let fileManager = FileManager.default
        let resourceKeys: Set<URLResourceKey> = [.isDirectoryKey, .isSymbolicLinkKey]
        let ignoredDirectories = Set([
            "node_modules", ".build", "DerivedData", ".cache", "Library",
            "Applications", "Movies", "Music", "Pictures", ".Trash",
        ])
        var pending: [(url: URL, depth: Int)] = [(root, 0)]
        var checkouts: [String] = []

        while let next = pending.popLast() {
            let directory = next.url
            let gitMarker = directory.appendingPathComponent(".git")
            if fileManager.fileExists(atPath: gitMarker.path) {
                checkouts.append(directory.path)
                continue
            }
            if let maximumDepth, next.depth >= maximumDepth { continue }

            guard let children = try? fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: Array(resourceKeys),
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else { continue }

            for child in children where !ignoredDirectories.contains(child.lastPathComponent) {
                guard let values = try? child.resourceValues(forKeys: resourceKeys),
                      values.isDirectory == true,
                      values.isSymbolicLink != true else { continue }
                pending.append((child, next.depth + 1))
            }
        }
        return checkouts
    }

    static func parseGitHubRepository(from remote: String) -> String? {
        var value = remote.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }

        if value.hasPrefix("git@github.com:") {
            value.removeFirst("git@github.com:".count)
        } else if let url = URL(string: value),
                  url.host?.lowercased() == "github.com" {
            value = url.path
        } else {
            return nil
        }

        value = value.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if value.lowercased().hasSuffix(".git") { value.removeLast(4) }
        let components = value.split(separator: "/", omittingEmptySubsequences: true)
        guard components.count == 2 else { return nil }
        return "\(components[0])/\(components[1])"
    }

    private static func originURL(in checkout: String) -> String? {
        let git = Process()
        git.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        git.arguments = ["-C", checkout, "remote", "get-url", "origin"]
        let output = Pipe()
        git.standardOutput = output
        git.standardError = Pipe()
        do { try git.run() } catch { return nil }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        git.waitUntilExit()
        guard git.terminationStatus == 0 else { return nil }
        return String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func isPreferred(_ candidate: String, over existing: String) -> Bool {
        let candidateDepth = URL(fileURLWithPath: candidate).pathComponents.count
        let existingDepth = URL(fileURLWithPath: existing).pathComponents.count
        if candidateDepth != existingDepth { return candidateDepth < existingDepth }
        return candidate.localizedCaseInsensitiveCompare(existing) == .orderedAscending
    }
}
