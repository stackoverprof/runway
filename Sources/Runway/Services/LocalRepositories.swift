import Foundation

struct LocalRepository: Equatable, Sendable {
    let nameWithOwner: String
    let path: String
}

enum LocalRepositoryDirectory {
    /// Scan where the user pointed Runway, as deep as they allowed. Defaults to
    /// the home directory at depth 6, which is what it always did.
    static func discoverOnDevice() -> [LocalRepository] {
        let search = SettingsKey.cloneSearch()
        return discover(in: search.root, maximumDepth: search.depth)
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

        // Every full clone gets its own row, so a second copy of a repository
        // (~/Developer/monosentry next to ~/Developer/monorepo/main) can be
        // picked on its own. Linked worktrees still collapse into their
        // repository: they only stand in when no full clone exists.
        var byRepository: [String: [LocalRepository]] = [:]
        for checkout in checkouts {
            guard let remote = originURL(in: checkout),
                  let repository = parseGitHubRepository(from: remote) else { continue }
            byRepository[repository.lowercased(), default: []]
                .append(LocalRepository(nameWithOwner: repository, path: checkout))
        }

        return byRepository.values.flatMap { group -> [LocalRepository] in
            let ordered = group.sorted { isPreferred($0, over: $1) }
            let clones = ordered.filter { isFullClone($0.path) }
            return clones.isEmpty ? Array(ordered.prefix(1)) : clones
        }.sorted {
            let order = $0.nameWithOwner.localizedCaseInsensitiveCompare($1.nameWithOwner)
            if order != .orderedSame { return order == .orderedAscending }
            return isPreferred($0, over: $1)
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

    /// A full clone has a `.git` directory; a linked worktree has a `.git` file.
    private static func isFullClone(_ checkout: String) -> Bool {
        var isDirectory: ObjCBool = false
        let marker = URL(fileURLWithPath: checkout).appendingPathComponent(".git").path
        return FileManager.default.fileExists(atPath: marker, isDirectory: &isDirectory)
            && isDirectory.boolValue
    }

    /// The checkout named after its repository wins (`monorepo`, or the
    /// `monorepo/main` of a worktree container), then the shallowest path.
    /// Depth alone let a sibling copy like `~/Developer/monosentry` outrank
    /// `~/Developer/monorepo/main`.
    private static func isPreferred(_ candidate: LocalRepository, over existing: LocalRepository) -> Bool {
        let candidateNamed = isNamedAfterRepository(candidate)
        if candidateNamed != isNamedAfterRepository(existing) { return candidateNamed }
        let candidateDepth = URL(fileURLWithPath: candidate.path).pathComponents.count
        let existingDepth = URL(fileURLWithPath: existing.path).pathComponents.count
        if candidateDepth != existingDepth { return candidateDepth < existingDepth }
        return candidate.path.localizedCaseInsensitiveCompare(existing.path) == .orderedAscending
    }

    private static func isNamedAfterRepository(_ checkout: LocalRepository) -> Bool {
        guard let name = checkout.nameWithOwner.split(separator: "/").last?.lowercased() else {
            return false
        }
        let url = URL(fileURLWithPath: checkout.path)
        let folder = url.lastPathComponent.lowercased()
        let parent = url.deletingLastPathComponent().lastPathComponent.lowercased()
        return folder == name || (folder == "main" && parent == name)
    }
}
