import Foundation
import Testing
@testable import Runway

@Suite("Focus movement log")
struct FocusMovementLogTests {
    private func write(_ lines: [String]) throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("focus-\(UUID().uuidString).jsonl")
        try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func row(_ repository: String, _ timestamp: String, cause: String = "user") -> String {
        """
        {"schemaVersion":1,"id":"\(UUID().uuidString)","timestamp":"\(timestamp)",\
        "timeZone":"Asia/Jakarta","action":"entered_focus","repository":"\(repository)",\
        "issueNumber":1,"issueTitle":"t","issueState":"OPEN","fromLane":"open",\
        "toLane":"focus","cause":"\(cause)"}
        """
    }

    @Test("The newest movement per repository wins")
    func keepsLatestPerRepository() throws {
        let file = try write([
            row("owner/one", "2026-08-01T10:00:00Z"),
            row("owner/one", "2026-08-20T10:00:00Z"),
            row("owner/two", "2026-08-10T10:00:00Z"),
        ])
        let latest = FocusActivityLog.latestMovementByRepository(in: file)
        #expect(latest.count == 2)
        #expect(latest["owner/one"] == ISO8601DateFormatter().date(from: "2026-08-20T10:00:00Z"))
        #expect(latest["owner/two"] != nil)
    }

    @Test("The first-seen snapshot is not movement")
    func ignoresSeededSnapshots() throws {
        let file = try write([
            row("owner/seeded", "2026-08-25T10:00:00Z", cause: "initial_snapshot"),
        ])
        #expect(FocusActivityLog.latestMovementByRepository(in: file).isEmpty)
    }

    @Test("A torn or unknown line never costs the rest of the log")
    func survivesBadLines() throws {
        let file = try write([
            "{not json",
            "",
            row("owner/good", "2026-08-22T10:00:00Z"),
            "{\"repository\":\"owner/partial\"}",
        ])
        let latest = FocusActivityLog.latestMovementByRepository(in: file)
        #expect(latest.keys.sorted() == ["owner/good"])
    }

    @Test("A missing log is simply no movement")
    func missingFileIsEmpty() {
        let missing = URL(fileURLWithPath: "/no/such/runway/focus-activity.jsonl")
        #expect(FocusActivityLog.latestMovementByRepository(in: missing).isEmpty)
    }
}
