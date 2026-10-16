import Foundation
import Testing
@testable import Runway

@Suite("Issue list scroll identity")
struct RunwayIssueListIdentityTests {
    @Test("An issue arriving on its own rebuilds the scroll view so a stale offset cannot hide it")
    func arrivalRebuilds() {
        #expect(RunwayIssueListIdentity.hasArrivals(from: [57], to: [72, 57], movedByUser: nil))
    }

    @Test("A card dragged into Focus keeps the lane's scroll view, and its place")
    func departureKeepsScroll() {
        #expect(!RunwayIssueListIdentity.hasArrivals(from: [72, 57, 40], to: [72, 40], movedByUser: 57))
    }

    @Test("The card the user dropped in does not count as an arrival")
    func userDropKeepsScroll() {
        #expect(!RunwayIssueListIdentity.hasArrivals(from: [72, 40], to: [72, 57, 40], movedByUser: 57))
        #expect(RunwayIssueListIdentity.hasArrivals(from: [72, 40], to: [72, 57, 40, 9], movedByUser: 57))
    }

    @Test("Reordering the same issues preserves the scroll view during drag")
    func reorderKeepsScroll() {
        #expect(!RunwayIssueListIdentity.hasArrivals(from: [72, 57], to: [57, 72], movedByUser: nil))
    }

    @Test("Reset recreates the scroll view")
    func resetRebuildsScroll() {
        let before = RunwayIssueListIdentity(
            repository: "owner/repo", lane: .open, query: "", arrivals: 0, resetGeneration: 0
        )
        let after = RunwayIssueListIdentity(
            repository: "owner/repo", lane: .open, query: "", arrivals: 0, resetGeneration: 1
        )
        #expect(before != after)
    }
}
