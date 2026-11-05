import Foundation
import Observation
import SwiftUI

/// How you have arranged the board: what order the flights sit in, and what
/// priority you gave each one.
///
/// Neither belongs to GitHub. The order is yours, and the priority is the one
/// you would say out loud, so both live beside Runway's other state and
/// follow the repository they were set in.
@MainActor
@Observable
final class FlightBoard {
    static let shared = FlightBoard()

    private struct Repo: Codable {
        var order: [Int] = []
        var priority: [String: Int] = [:]
        /// Pinned flights, in the order they were pinned. They sit above the
        /// rest in either sort.
        var pinned: [Int] = []

        init() {}

        // Spelled out so a board.json written before pins still loads.
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            order = try c.decodeIfPresent([Int].self, forKey: .order) ?? []
            priority = try c.decodeIfPresent([String: Int].self, forKey: .priority) ?? [:]
            pinned = try c.decodeIfPresent([Int].self, forKey: .pinned) ?? []
        }
    }

    private var repos: [String: Repo] = [:]
    private var stamp: Date?

    private var file: URL {
        RunwayStorage.supportDir.appendingPathComponent("board.json")
    }

    private init() { load() }

    // MARK: Order

    /// The flights in the lane's order: pinned ones first, then the rest,
    /// either as you dragged them (free) or by last activity (recent).
    func ordered(_ flights: [AssignedIssue], in repository: String) -> [AssignedIssue] {
        let sorted: [AssignedIssue]
        switch FlightSort.current {
        case .free: sorted = freeOrder(flights, in: repository)
        case .priority:
            // P1 first, unset last. Within one class, the flights in the air
            // come first, furthest along first, then the scheduled ones; the
            // newest issue breaks what is left.
            let rank = { (flight: AssignedIssue) in self.priority(flight.number, in: repository) ?? 99 }
            let along = { (flight: AssignedIssue) -> Double in
                guard FlightStatus.of(flight) == .onAir else { return -1 }
                let flown = FlightStatus.transits(of: flight)
                return flown.total > 0 ? Double(flown.done) / Double(flown.total) : 0
            }
            sorted = flights
                .map { ($0, rank($0), along($0)) }
                .sorted {
                    if $0.1 != $1.1 { return $0.1 < $1.1 }
                    if $0.2 != $1.2 { return $0.2 > $1.2 }
                    return $0.0.number > $1.0.number
                }
                .map(\.0)
        case .number:
            sorted = flights.sorted { $0.number > $1.number }
        case .recent:
            let activity = FlightActivity.shared
            let now = Date()
            sorted = flights
                .map { ($0, activity.rank($0, now: now)) }
                .sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.0.number > $1.0.number }
                .map(\.0)
        }
        let pins = repos[repository]?.pinned ?? []
        guard !pins.isEmpty else { return sorted }
        // Pins keep their own order, the one you dragged them into, in
        // either sort, as T3 Code's pinned block does.
        let byNumber = Dictionary(sorted.map { ($0.number, $0) }, uniquingKeysWith: { first, _ in first })
        let pinSet = Set(pins)
        return pins.compactMap { byNumber[$0] } + sorted.filter { !pinSet.contains($0.number) }
    }

    /// The flights in the order you put them, with any you have not placed
    /// yet at the front, newest first.
    private func freeOrder(_ flights: [AssignedIssue], in repository: String) -> [AssignedIssue] {
        let saved = repos[repository]?.order ?? []
        let byNumber = Dictionary(flights.map { ($0.number, $0) }, uniquingKeysWith: { first, _ in first })
        let placed = saved.compactMap { byNumber[$0] }
        let placedNumbers = Set(placed.map(\.number))
        let fresh = flights
            .filter { !placedNumbers.contains($0.number) }
            .sorted { $0.number > $1.number }
        return fresh + placed
    }

    /// A drag in the lane. A pinned card reorders the pins; any other card
    /// reorders the free list, which only exists in free mode.
    func reorder(_ lane: [Int], moving number: Int, in repository: String) {
        var repo = repos[repository] ?? Repo()
        // The lane is one group, pinned or not; a drag never crosses groups.
        let pinSet = Set(repo.pinned)
        if pinSet.contains(number) {
            let visible = lane.filter { pinSet.contains($0) }
            let hidden = repo.pinned.filter { !visible.contains($0) }
            repo.pinned = visible + hidden
        } else {
            guard FlightSort.current == .free else { return }
            repo.order = lane.filter { !pinSet.contains($0) }
        }
        repos[repository] = repo
        save()
    }

    // MARK: Pins

    func isPinned(_ number: Int, in repository: String) -> Bool {
        repos[repository]?.pinned.contains(number) ?? false
    }

    func setPinned(_ pinned: Bool, for number: Int, in repository: String) {
        var repo = repos[repository] ?? Repo()
        repo.pinned.removeAll { $0 == number }
        if pinned {
            repo.pinned.append(number)
        } else {
            // Unpinned, it lands at the top of the rest, right under the line.
            repo.order.removeAll { $0 == number }
            repo.order.insert(number, at: 0)
        }
        repos[repository] = repo
        save()
    }

    func setOrder(_ numbers: [Int], in repository: String) {
        var repo = repos[repository] ?? Repo()
        repo.order = numbers
        repos[repository] = repo
        save()
    }

    // MARK: Priority

    /// 1 to 5, or nil when you have not said.
    func priority(_ number: Int, in repository: String) -> Int? {
        repos[repository]?.priority[String(number)]
    }

    func setPriority(_ priority: Int?, for number: Int, in repository: String) {
        var repo = repos[repository] ?? Repo()
        if let priority { repo.priority[String(number)] = priority }
        else { repo.priority.removeValue(forKey: String(number)) }
        repos[repository] = repo
        save()
    }

    // MARK: Disk

    /// Reread when the file has moved on, which is how `runway order` and
    /// `runway priority` from an agent reach the pane.
    func reload() {
        let modified = (try? FileManager.default
            .attributesOfItem(atPath: file.path)[.modificationDate] as? Date) ?? nil
        guard modified != stamp else { return }
        load()
    }

    private func load() {
        stamp = (try? FileManager.default
            .attributesOfItem(atPath: file.path)[.modificationDate] as? Date) ?? nil
        guard let data = try? Data(contentsOf: file),
              let decoded = try? JSONDecoder().decode([String: Repo].self, from: data)
        else { return }
        repos = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(repos) else { return }
        try? FileManager.default.createDirectory(
            at: RunwayStorage.supportDir,
            withIntermediateDirectories: true
        )
        try? data.write(to: file)
        stamp = (try? FileManager.default
            .attributesOfItem(atPath: file.path)[.modificationDate] as? Date) ?? nil
    }
}

/// How the open lane is sorted. Set in Settings > Flights.
enum FlightSort: String, CaseIterable {
    /// Where you dragged them.
    case free
    /// P1 first.
    case priority
    /// The flight you last opened or typed into first.
    case recent
    /// Newest issue first.
    case number

    static let key = "runway.flightSort"

    static var current: FlightSort {
        FlightSort(rawValue: UserDefaults.standard.string(forKey: key) ?? "") ?? .free
    }

    var label: String {
        switch self {
        case .free: "Drag to arrange"
        case .priority: "By priority (P1 first, then furthest along)"
        case .recent: "By recency (last touched first)"
        case .number: "By issue number (newest first)"
        }
    }
}

/// What a priority looks like: P1 is on fire, P5 can wait.
enum FlightPriority {
    static let all = [1, 2, 3, 4, 5]

    static func label(_ value: Int) -> String { "P\(value)" }

    /// Red at P1, cooling to blue at P5.
    static func color(_ value: Int) -> Color {
        switch value {
        case 1: Color(red: 0.898, green: 0.349, blue: 0.310)  // #e5594f
        case 2: Color(red: 0.910, green: 0.569, blue: 0.228)  // #e8913a
        case 3: Color(red: 0.847, green: 0.761, blue: 0.290)  // #d8c24a
        case 4: Color(red: 0.37, green: 0.75, blue: 0.62)
        default: Color(red: 0.38, green: 0.60, blue: 0.93)
        }
    }
}
