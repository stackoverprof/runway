import Foundation
import Testing
@testable import Runway

@Suite("Quick terminal sessions")
struct QuickTerminalSessionTests {
    @Test("Each repository gets its own stable conversation")
    func perRepositoryIdentity() {
        let a = QuickTerminalSession.id(provider: .claude, repository: "owner/repo-a", generation: 0)
        let b = QuickTerminalSession.id(provider: .claude, repository: "owner/repo-b", generation: 0)
        #expect(a != nil)
        #expect(a != b)
        #expect(a == QuickTerminalSession.id(provider: .claude, repository: "Owner/Repo-A", generation: 0))
    }

    @Test("Starting a new session changes the id, permanently")
    func generationRotatesID() {
        let before = QuickTerminalSession.id(provider: .claude, repository: "owner/repo", generation: 3)
        let after = QuickTerminalSession.id(provider: .claude, repository: "owner/repo", generation: 4)
        #expect(before != after)
    }

    @Test("Quick and Focus sessions never collide, nor do providers")
    func distinctNamespaces() {
        let quick = QuickTerminalSession.id(provider: .claude, repository: "owner/repo", generation: 0)
        let issue = IssueAgentSession.id(provider: .claude, repository: "owner/repo", issueNumber: 0)
        #expect(quick != issue)
        let gemini = QuickTerminalSession.id(provider: .gemini, repository: "owner/repo", generation: 0)
        #expect(quick != gemini)
    }

    @Test("No repository, no session")
    func emptyRepository() {
        #expect(QuickTerminalSession.id(provider: .claude, repository: "", generation: 0) == nil)
    }

    @Test("Ids are valid v4 UUIDs for the provider CLIs")
    func uuidShape() {
        let id = QuickTerminalSession.id(provider: .claude, repository: "owner/repo", generation: 0)!
        let text = id.uuidString
        #expect(text[text.index(text.startIndex, offsetBy: 14)] == "4")
        #expect("89AB".contains(text[text.index(text.startIndex, offsetBy: 19)]))
    }
}
