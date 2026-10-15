import Foundation
import Testing
@testable import Runway

@Suite("Local repository discovery")
struct LocalRepositoriesTests {
    @Test("Parses common GitHub origin URL formats", arguments: [
        "https://github.com/VISKA-IO/monorepo.git",
        "git@github.com:VISKA-IO/monorepo.git",
        "ssh://git@github.com/VISKA-IO/monorepo.git",
    ])
    func parsesGitHubOrigin(_ remote: String) {
        #expect(
            LocalRepositoryDirectory.parseGitHubRepository(from: remote)
                == "VISKA-IO/monorepo"
        )
    }

    @Test("Rejects non-GitHub and malformed origins", arguments: [
        "https://gitlab.com/VISKA-IO/monorepo.git",
        "https://github.com/VISKA-IO",
        "",
    ])
    func rejectsUnsupportedOrigin(_ remote: String) {
        #expect(LocalRepositoryDirectory.parseGitHubRepository(from: remote) == nil)
    }

    @Test("Discovers local clones, the one named after the repository first")
    func discoversLocalClones() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let primary = root.appendingPathComponent("Developer/monorepo", isDirectory: true)
        let worktree = root.appendingPathComponent("Developer/agents/mono1", isDirectory: true)
        try makeRepository(at: primary, remote: "https://github.com/VISKA-IO/monorepo.git")
        try makeRepository(at: worktree, remote: "git@github.com:VISKA-IO/monorepo.git")

        let discovered = LocalRepositoryDirectory.discover(in: root.path)
        #expect(discovered.count == 2)
        #expect(discovered.first?.nameWithOwner == "VISKA-IO/monorepo")
        #expect(URL(fileURLWithPath: discovered.first?.path ?? "").lastPathComponent == "monorepo")
        #expect(
            LocalRepositoryDirectory.directCheckoutPath(
                for: "VISKA-IO/monorepo",
                homePath: root.path
            ) == discovered.first?.path
        )
    }

    @Test("Lists a second clone of one repository as its own checkout")
    func listsSecondClone() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let main = root.appendingPathComponent("Developer/monorepo/main", isDirectory: true)
        let copy = root.appendingPathComponent("Developer/monosentry", isDirectory: true)
        let worktree = root.appendingPathComponent("Developer/monorepo/fix-thing-1", isDirectory: true)
        try makeRepository(at: main, remote: "https://github.com/VISKA-IO/monorepo.git")
        try makeRepository(at: copy, remote: "https://github.com/VISKA-IO/monorepo.git")
        try runGit(["-C", main.path, "commit", "--quiet", "--allow-empty", "-m", "init"])
        try runGit(["-C", main.path, "worktree", "add", "--quiet", worktree.path, "-b", "fix/thing-1"])

        let discovered = LocalRepositoryDirectory.discover(in: root.path)
        // The worktree folds into its repository; both full clones stay, and
        // the one named after the repository comes first although it is deeper.
        #expect(discovered.map { URL(fileURLWithPath: $0.path).lastPathComponent }
            == ["main", "monosentry"])
        #expect(discovered.allSatisfy { $0.nameWithOwner == "VISKA-IO/monorepo" })
    }

    private func makeRepository(at url: URL, remote: String) throws {
        try FileManager.default.createDirectory(
            at: url,
            withIntermediateDirectories: true
        )
        try runGit(["init", "--quiet", url.path])
        try runGit(["-C", url.path, "remote", "add", "origin", remote])
        try runGit(["-C", url.path, "config", "user.email", "test@example.com"])
        try runGit(["-C", url.path, "config", "user.name", "Test"])
    }

    private func runGit(_ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        try process.run()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0)
    }
}
