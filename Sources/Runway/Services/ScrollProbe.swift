import AppKit
import Foundation

/// A temporary ear on the scroll monitor, to find out what the ATC panel is
/// actually receiving. Writes one line per scroll event; delete when the
/// question is answered.
@MainActor
enum ScrollProbe {
    private static let file = RunwayStorage.supportDir.appendingPathComponent("scroll-probe.log")
    private static var count = 0

    static func note(terminal: Bool, event: NSEvent) {
        count += 1
        guard count < 400 else { return }
        let line = String(
            format: "%@ terminal=%@ quick=%@ precise=%@ momentum=%d dy=%.2f phase=%d\n",
            ISO8601DateFormatter().string(from: Date()),
            terminal ? "y" : "n",
            event.hasPreciseScrollingDeltas ? "y" : "n",
            event.momentumPhase.rawValue,
            event.scrollingDeltaY,
            event.phase.rawValue
        )
        guard let data = line.data(using: .utf8) else { return }
        if let handle = try? FileHandle(forWritingTo: file) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: file)
        }
    }
}
