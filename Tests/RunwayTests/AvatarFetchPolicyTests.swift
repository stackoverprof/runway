import AppKit
import Testing
@testable import Runway

@Suite("Avatar fetch policy")
struct AvatarFetchPolicyTests {
    private func pngData() -> Data {
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2, bitsPerSample: 8,
            samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        return rep.representation(using: .png, properties: [:])!
    }

    @Test("Only 2xx (or non-HTTP) responses are accepted")
    func statuses() {
        #expect(AvatarFetchPolicy.acceptsStatus(200))
        #expect(AvatarFetchPolicy.acceptsStatus(204))
        #expect(AvatarFetchPolicy.acceptsStatus(nil))
        #expect(!AvatarFetchPolicy.acceptsStatus(304))
        #expect(!AvatarFetchPolicy.acceptsStatus(404))
        #expect(!AvatarFetchPolicy.acceptsStatus(429))
        #expect(!AvatarFetchPolicy.acceptsStatus(503))
    }

    @Test("A real image on 200 decodes; error bodies and bad statuses do not")
    func decoding() {
        let png = pngData()
        #expect(AvatarFetchPolicy.image(from: png, status: 200) != nil)
        #expect(AvatarFetchPolicy.image(from: png, status: 429) == nil)
        #expect(AvatarFetchPolicy.image(from: Data("rate limited".utf8), status: 200) == nil)
        #expect(AvatarFetchPolicy.image(from: Data(), status: 200) == nil)
    }

    @Test("Retries back off and stay bounded")
    func backoff() {
        let delays = AvatarFetchPolicy.retryDelays
        #expect(delays == [.seconds(1), .seconds(3), .seconds(10)])
        #expect(zip(delays, delays.dropFirst()).allSatisfy { $0 < $1 })
        #expect(AvatarFetchPolicy.revisitDelays.allSatisfy { $0 > delays.last! })
    }

    @Test("Disk names are stable, distinct per URL, and path-safe")
    func diskNames() {
        let a = AvatarFetchPolicy.diskFileName(for: "https://github.com/stackoverprof.png?size=96")
        let b = AvatarFetchPolicy.diskFileName(for: "https://github.com/stackoverprof.png?size=96")
        let c = AvatarFetchPolicy.diskFileName(for: "https://github.com/octocat.png?size=96")
        #expect(a == b)
        #expect(a != c)
        #expect(a.hasSuffix(".img"))
        #expect(a.count == 64 + 4)
        #expect(!a.contains("/") && !a.contains("?"))
    }
}
