import Testing
@testable import Runway

@Suite("Feed reveal policy")
struct FeedRevealPolicyTests {
    @Test("A handful of new events still cascades in")
    func smallBurstStaggers() {
        #expect(FeedRevealPolicy.staggers(1))
        #expect(FeedRevealPolicy.staggers(FeedRevealPolicy.maxStaggered))
    }

    @Test("A backlog from hours away lands at once instead of animating for a minute")
    func largeBurstLandsAtOnce() {
        #expect(!FeedRevealPolicy.staggers(FeedRevealPolicy.maxStaggered + 1))
        #expect(!FeedRevealPolicy.staggers(120))
    }

    @Test("Nothing new means nothing to reveal")
    func emptyBurst() {
        #expect(!FeedRevealPolicy.staggers(0))
        #expect(!FeedRevealPolicy.animatesBatch(0))
    }

    @Test("A moderate batch still animates, a huge one just appears")
    func batchAnimationCutoff() {
        #expect(FeedRevealPolicy.animatesBatch(FeedRevealPolicy.maxStaggered + 1))
        #expect(FeedRevealPolicy.animatesBatch(FeedRevealPolicy.maxAnimatedBatch))
        #expect(!FeedRevealPolicy.animatesBatch(FeedRevealPolicy.maxAnimatedBatch + 1))
    }
}
