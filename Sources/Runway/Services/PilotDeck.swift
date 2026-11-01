import Foundation
import Observation

/// Which pilots are up, held where an agent can reach it.
///
/// A crew could always be stood up from outside the window: `runway crew up`
/// writes the crew deck and the right pane mounts the seat. A pilot could
/// not. Its terminal lived only while its flight was the one on screen, so
/// the only way to start seven pilots was to click seven cards, and an ATC
/// session asked to brief them all had no move to make.
///
/// This is the same deck for the other rank. A flight on it keeps its pilot
/// and copilot seats mounted whether or not you are looking at it, so the
/// agent starts, registers its session, and can be messaged. Taking it off
/// the deck lets the pane drop it again.
@MainActor
@Observable
final class PilotDeck {
    static let shared = PilotDeck()

    /// Flights whose seats stay up, as `owner/repo#number`.
    private(set) var up: Set<String> = []
    private var stamp: Date?
    private var since: [String: Date] = [:]

    private var file: URL {
        RunwayStorage.supportDir.appendingPathComponent("pilot-deck.json")
    }

    private init() { reload(force: true) }

    static func seat(_ repository: String, _ number: Int) -> String {
        "\(repository)#\(number)"
    }

    func isUp(_ repository: String, _ number: Int) -> Bool {
        up.contains(Self.seat(repository, number))
    }

    /// The flights on the deck for one repository, as plain numbers.
    func flights(in repository: String) -> [Int] {
        let prefix = "\(repository)#"
        return up
            .filter { $0.hasPrefix(prefix) }
            .compactMap { Int($0.dropFirst(prefix.count)) }
            .sorted()
    }

    func bringUp(_ repository: String, _ number: Int, title: String = "") {
        let seat = Self.seat(repository, number)
        guard !up.contains(seat) else { return }
        var next = up
        next.insert(seat)
        since[seat] = Date()
        write(next)
        ActivityLog.pilotUp(number, title: title, repository: repository)
    }

    func standDown(_ repository: String, _ number: Int, title: String = "") {
        let seat = Self.seat(repository, number)
        guard up.contains(seat) else { return }
        var next = up
        next.remove(seat)
        let ran = since.removeValue(forKey: seat).map { Int(Date().timeIntervalSince($0)) } ?? 0
        write(next)
        ActivityLog.pilotDown(number, title: title, repository: repository, seconds: ran)
    }

    /// Reread when the file has moved on, which is how an agent's write
    /// reaches the pane.
    func reload(force: Bool = false) {
        let modified = (try? FileManager.default
            .attributesOfItem(atPath: file.path)[.modificationDate] as? Date) ?? nil
        if !force, modified == stamp { return }
        stamp = modified
        guard let data = try? Data(contentsOf: file),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let seats = json["up"] as? [String] else {
            if !up.isEmpty { up = [] }
            return
        }
        let next = Set(seats)
        if next != up { up = next }
    }

    private func write(_ next: Set<String>) {
        up = next
        let json: [String: Any] = ["up": next.sorted()]
        guard let data = try? JSONSerialization.data(
            withJSONObject: json,
            options: [.prettyPrinted, .sortedKeys]
        ) else { return }
        try? FileManager.default.createDirectory(
            at: RunwayStorage.supportDir,
            withIntermediateDirectories: true
        )
        try? data.write(to: file)
        stamp = (try? FileManager.default
            .attributesOfItem(atPath: file.path)[.modificationDate] as? Date) ?? nil
    }
}
