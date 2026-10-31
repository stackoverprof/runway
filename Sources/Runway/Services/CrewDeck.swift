import Foundation
import Observation

/// Which crews are up, held where the pilot can reach it.
///
/// Standing a crew up or down was a thing only the right pane knew, so a pilot
/// could tell you what to click but could not do it. The deck is a small file
/// both sides read and write: the buttons in the pane, and `runway crew up` /
/// `runway crew down` from an agent. Whoever writes it, the other sees it
/// within a second.
@MainActor
@Observable
final class CrewDeck {
    static let shared = CrewDeck()

    /// Crews that are up, as `owner/repo#number`.
    private(set) var up: Set<String> = []
    private var stamp: Date?

    private var file: URL {
        RunwayStorage.supportDir.appendingPathComponent("crew-deck.json")
    }

    private init() { reload(force: true) }

    static func seat(_ repository: String, _ number: Int) -> String {
        "\(repository)#\(number)"
    }

    func isUp(_ repository: String, _ number: Int) -> Bool {
        up.contains(Self.seat(repository, number))
    }

    /// When each crew came up, so standing it down can say how long it ran.
    private var since: [String: Date] = [:]

    func bringUp(_ repository: String, _ number: Int, title: String = "") {
        let seat = Self.seat(repository, number)
        guard !up.contains(seat) else { return }
        var next = up
        next.insert(seat)
        since[seat] = Date()
        write(next)
        ActivityLog.crewUp(number, title: title, repository: repository)
    }

    func standDown(_ repository: String, _ number: Int, title: String = "") {
        let seat = Self.seat(repository, number)
        guard up.contains(seat) else { return }
        var next = up
        next.remove(seat)
        let ran = since.removeValue(forKey: seat).map { Int(Date().timeIntervalSince($0)) } ?? 0
        write(next)
        ActivityLog.crewDown(number, title: title, repository: repository, seconds: ran)
    }

    /// A closed crew leaves the pane, so it leaves the deck with it.
    func forget(_ repository: String, _ number: Int) {
        standDown(repository, number)
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
            if up.isEmpty == false { up = [] }
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
