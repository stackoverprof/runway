import Foundation
import Testing
@testable import Runway

/// Why the state pulse exists at all.
///
/// A control file is rewritten in place, which changes no directory entry, so a
/// watcher on the control directory never hears about it and the amber state
/// only surfaced on the next poll. An append is a write to a file that can be
/// watched directly. These tests pin both halves of that claim.
@Suite("State pulse watch", .serialized)
struct StatePulseWatchTests {
    private func temporaryDirectory() throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("pulse-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Watch `path` and return whether the handler fired within the timeout.
    private func firesEvent(
        watching path: String,
        mask: DispatchSource.FileSystemEvent,
        timeout: TimeInterval,
        whenChanging change: () throws -> Void
    ) throws -> Bool {
        let descriptor = open(path, O_EVTONLY)
        #expect(descriptor >= 0)
        defer { close(descriptor) }

        let fired = DispatchSemaphore(value: 0)
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: mask,
            queue: DispatchQueue.global()
        )
        source.setEventHandler { fired.signal() }
        source.resume()
        defer { source.cancel() }

        try change()
        return fired.wait(timeout: .now() + timeout) == .success
    }

    @Test("An appended pulse wakes a watcher at once")
    func appendWakesTheWatcher() throws {
        let directory = try temporaryDirectory()
        let pulse = directory.appendingPathComponent("state-pulse")
        FileManager.default.createFile(atPath: pulse.path, contents: nil)

        let woke = try firesEvent(
            watching: pulse.path,
            mask: [.write, .extend, .delete, .rename],
            timeout: 1
        ) {
            let handle = try FileHandle(forWritingTo: pulse)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: Data(".".utf8))
        }
        #expect(woke)
    }

    @Test("Rewriting a control file in place wakes no directory watcher")
    func inPlaceRewriteIsInvisibleToTheDirectory() throws {
        let directory = try temporaryDirectory()
        let control = directory.appendingPathComponent("box.json")
        try Data(#"{"state":"running"}"#.utf8).write(to: control)

        let woke = try firesEvent(
            watching: directory.path,
            mask: .write,
            timeout: 0.5
        ) {
            // Exactly what the hook does: truncate and rewrite the same path.
            try Data(#"{"state":"needs-action"}"#.utf8).write(to: control)
        }
        #expect(!woke, "if this starts passing, the pulse file is redundant")
    }

    @Test("Trimming leaves a small pulse file alone and empties a large one")
    func trimOnlyRunsWhenItHasTo() throws {
        AgentControl.ensureStatePulse()
        try Data(repeating: 0x2E, count: 32).write(to: AgentControl.statePulse)
        AgentControl.trimStatePulse(largerThan: 1024)
        #expect(try Data(contentsOf: AgentControl.statePulse).count == 32)

        try Data(repeating: 0x2E, count: 4096).write(to: AgentControl.statePulse)
        AgentControl.trimStatePulse(largerThan: 1024)
        #expect(try Data(contentsOf: AgentControl.statePulse).isEmpty)
    }
}
