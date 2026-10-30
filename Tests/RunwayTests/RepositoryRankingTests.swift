import Foundation
import Testing
@testable import Runway

@Suite("Repository picker order")
struct RepositoryRankingTests {
    @Test("The most recently selected comes first")
    func recentsLead() {
        let ranked = RepositoryRanking.ranked(
            ["owner/idle", "owner/old", "owner/fresh"],
            recents: ["owner/fresh", "owner/old"]
        )
        #expect(ranked == ["owner/fresh", "owner/old", "owner/idle"])
    }

    @Test("Repositories never selected fall in alphabetically behind the rest")
    func alphabeticalTail() {
        let ranked = RepositoryRanking.ranked(
            ["owner/zulu", "owner/alpha", "owner/picked"],
            recents: ["owner/picked"]
        )
        #expect(ranked == ["owner/picked", "owner/alpha", "owner/zulu"])
    }

    @Test("Case never splits one repository into two places")
    func caseInsensitive() {
        let ranked = RepositoryRanking.ranked(
            ["Owner/Repo", "owner/other"],
            recents: ["owner/repo"]
        )
        #expect(ranked == ["Owner/Repo", "owner/other"])
    }

    @Test("The order never depends on the order they arrived in")
    func totalOrder() {
        let one = RepositoryRanking.ranked(["b/one", "a/two"], recents: [])
        let other = RepositoryRanking.ranked(["a/two", "b/one"], recents: [])
        #expect(one == other)
    }
}
