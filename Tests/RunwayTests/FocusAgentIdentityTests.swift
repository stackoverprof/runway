import Foundation
import Testing
@testable import Runway

@Suite("Focus agent identity")
struct FocusAgentIdentityTests {
    private func makeDirectory(_ path: String, in root: URL, git: Bool = false) throws -> URL {
        let url = root.appendingPathComponent(path, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        if git {
            try FileManager.default.createDirectory(
                at: url.appendingPathComponent(".git"),
                withIntermediateDirectories: true
            )
        }
        return url
    }

    private func temporaryRoot() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
    }

    @Test("A worktree container is named and entered at the container, not main")
    func containerCloneIsTheContainer() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let main = try makeDirectory("Developer/monorepo/main", in: root, git: true)

        #expect(CloneName.name(ofCheckout: main.path) == "monorepo")
        #expect(CloneName.root(ofCheckout: main.path) == main.deletingLastPathComponent().path)
    }

    @Test("A plain clone is its own folder")
    func plainClone() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let clone = try makeDirectory("Developer/monosentry", in: root, git: true)

        #expect(CloneName.name(ofCheckout: clone.path) == "monosentry")
        #expect(CloneName.root(ofCheckout: clone.path) == clone.path)
    }

    @Test("A main folder inside a real checkout stays main")
    func mainInsideACheckout() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        _ = try makeDirectory("Developer/tool", in: root, git: true)
        let inner = try makeDirectory("Developer/tool/main", in: root, git: true)

        #expect(CloneName.name(ofCheckout: inner.path) == "main")
    }

    @Test("A Focus terminal knows its issue and its agent name")
    func focusTerminalIdentity() {
        let environment = AgentControl.environment(
            for: UUID(),
            focusRepository: "VISKA-IO/monorepo",
            focusIssueNumber: 14202,
            focusIssueTitle: "Cust: Static pages for faster site loads",
            focusCheckoutPath: "/Users/someone/Developer/monosentry"
        )

        #expect(environment["RUNWAY_ISSUE"] == "VISKA-IO/monorepo#14202")
        #expect(environment["RUNWAY_ISSUE_TITLE"] == "Cust: Static pages for faster site loads")
        #expect(environment["RUNWAY_ISSUE_URL"] == "https://github.com/VISKA-IO/monorepo/issues/14202")
        #expect(environment["RUNWAY_CLONE"] == "monosentry")
        #expect(environment["RUNWAY_AGENT_NAME"] == "monosentry-14202")
    }

    @Test("The quick terminal and plain boxes carry no issue")
    func noIssueOutsideFocus() {
        let plain = AgentControl.environment(for: UUID())
        let quick = AgentControl.environment(
            for: UUID(),
            focusRepository: "VISKA-IO/monorepo",
            focusIssueNumber: 1,
            focusCheckoutPath: "/tmp/monorepo",
            quickTerminalSession: true
        )
        for environment in [plain, quick] {
            #expect(environment["RUNWAY_ISSUE"] == nil)
            #expect(environment["RUNWAY_AGENT_NAME"] == nil)
        }
    }

    @Test("Claude is told its issue every time a session starts, resumes or clears")
    func sessionStartTellsTheIssue() throws {
        let hooks = try #require(AgentControl.hookSettings["hooks"] as? [String: Any])
        let matchers = try #require(hooks["SessionStart"] as? [[String: Any]])
        let commands = try #require(matchers.first?["hooks"] as? [[String: Any]])
        #expect(commands.contains {
            ($0["command"] as? String)?.contains("runway-issue-context") == true
        })
    }

    private func runContextHook(_ environment: [String: String]) throws -> String {
        let script = FileManager.default.temporaryDirectory
            .appendingPathComponent("runway-issue-context-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: script) }
        try AgentControl.issueContextHookScript.write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)

        let process = Process()
        process.executableURL = script
        process.environment = environment
        let input = Pipe()
        let output = Pipe()
        process.standardInput = input
        process.standardOutput = output
        try process.run()
        input.fileHandleForWriting.write(Data(#"{"session_id":"x","source":"startup"}"#.utf8))
        try input.fileHandleForWriting.close()
        process.waitUntilExit()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        return String(decoding: data, as: UTF8.self)
    }

    @Test("The hook names the agent, the issue and how to read it")
    func contextHookPrintsTheIssue() throws {
        let text = try runContextHook([
            "RUNWAY_ISSUE": "VISKA-IO/monorepo#14202",
            "RUNWAY_ISSUE_TITLE": "Cust: Static pages for faster site loads",
            "RUNWAY_AGENT_NAME": "monorepo-14202",
        ])
        #expect(text.contains("You are monorepo-14202"))
        #expect(text.contains("VISKA-IO/monorepo#14202"))
        #expect(text.contains("Cust: Static pages for faster site loads"))
        #expect(text.contains("gh issue view 14202 --repo VISKA-IO/monorepo"))
        #expect(text.contains("Do not start work until the user asks"))
    }

    @Test("Outside a Focus terminal the hook says nothing")
    func contextHookSilentWithoutIssue() throws {
        #expect(try runContextHook([:]).isEmpty)
    }
}
