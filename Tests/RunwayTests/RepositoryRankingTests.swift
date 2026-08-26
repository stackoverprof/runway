import Foundation
import Testing
@testable import Runway

@Suite("Repository picker order")
struct RepositoryRankingTests {
    private func date(_ day: Int) -> Date {
        Date(timeIntervalSince1970: 1_780_000_000 + Double(day) * 86_400)
    }

    @Test("Boards that moved most recently come first")
    func focusMovementLeads() {
        let ranked = RepositoryRanking.ranked(
            ["owner/idle", "owner/old", "owner/fresh"],
            focusMovement: ["owner/old": date(1), "owner/fresh": date(9)],
            recents: []
        )
        #expect(ranked == ["owner/fresh", "owner/old", "owner/idle"])
    }

    @Test("A board that moved outranks a repository merely selected recently")
    func movementBeatsSelection() {
        let ranked = RepositoryRanking.ranked(
            ["owner/picked", "owner/worked"],
            focusMovement: ["owner/worked": date(2)],
            recents: ["owner/picked"]
        )
        #expect(ranked == ["owner/worked", "owner/picked"])
    }

    @Test("Repositories with no board movement fall back to last selected")
    func recentsOrderTheTail() {
        let ranked = RepositoryRanking.ranked(
            ["owner/a", "owner/b", "owner/c"],
            focusMovement: [:],
            recents: ["owner/c", "owner/b"]
        )
        #expect(ranked == ["owner/c", "owner/b", "owner/a"])
    }

    @Test("Never-touched clones sort alphabetically, not by scan order")
    func untouchedIsAlphabetical() {
        let ranked = RepositoryRanking.ranked(
            ["z/zebra", "a/apple", "M/middle"],
            focusMovement: [:],
            recents: []
        )
        #expect(ranked == ["a/apple", "M/middle", "z/zebra"])
    }

    @Test("Owner casing never splits a repository from its own history")
    func caseInsensitiveIdentity() {
        let ranked = RepositoryRanking.ranked(
            ["Owner/Idle", "OWNER/Worked"],
            focusMovement: ["owner/worked": date(3)],
            recents: ["owner/idle"]
        )
        #expect(ranked == ["OWNER/Worked", "Owner/Idle"])
    }

    @Test("Ranking one list twice gives the same order")
    func deterministicForEqualKeys() {
        let repositories = ["owner/b", "owner/a", "owner/c"]
        let movement = ["owner/a": date(4), "owner/b": date(4)]
        let first = RepositoryRanking.ranked(
            repositories,
            focusMovement: movement,
            recents: []
        )
        #expect(
            first == RepositoryRanking.ranked(
                repositories.reversed(),
                focusMovement: movement,
                recents: []
            )
        )
    }
}
