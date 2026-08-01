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

    @Test("Discovers local clones and prefers the shallowest checkout")
    func discoversLocalClones() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let primary = root.appendingPathComponent("Developer/monorepo", isDirectory: true)
        let worktree = root.appendingPathComponent("Developer/agents/mono1", isDirectory: true)
        try makeRepository(at: primary, remote: "https://github.com/VISKA-IO/monorepo.git")
        try makeRepository(at: worktree, remote: "git@github.com:VISKA-IO/monorepo.git")

        let discovered = LocalRepositoryDirectory.discover(in: root.path)
        #expect(discovered.count == 1)
        #expect(discovered.first?.nameWithOwner == "VISKA-IO/monorepo")
        #expect(URL(fileURLWithPath: discovered.first?.path ?? "").lastPathComponent == "monorepo")
        #expect(
            LocalRepositoryDirectory.directCheckoutPath(
                for: "VISKA-IO/monorepo",
                homePath: root.path
            ) == discovered.first?.path
        )
    }

    private func makeRepository(at url: URL, remote: String) throws {
        try FileManager.default.createDirectory(
            at: url,
            withIntermediateDirectories: true
        )
        try runGit(["init", "--quiet", url.path])
        try runGit(["-C", url.path, "remote", "add", "origin", remote])
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
