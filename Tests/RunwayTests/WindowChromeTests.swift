import CoreGraphics
import Testing
@testable import Runway

@Suite("Window chrome")
struct WindowChromeTests {
    @Test("Only the top edge is a window zoom target")
    func topEdgeZoomBand() {
        let bounds = CGRect(x: 0, y: 0, width: 1100, height: 720)

        #expect(WindowChrome.isInZoomBand(
            location: CGPoint(x: 500, y: 719),
            bounds: bounds
        ))
        #expect(!WindowChrome.isInZoomBand(
            location: CGPoint(x: 500, y: 700),
            bounds: bounds
        ))
        #expect(!WindowChrome.isInZoomBand(
            location: CGPoint(x: 1200, y: 719),
            bounds: bounds
        ))
    }
}
