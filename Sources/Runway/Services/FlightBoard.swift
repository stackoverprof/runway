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
    }

    private var repos: [String: Repo] = [:]
    private var stamp: Date?

    private var file: URL {
        RunwayStorage.supportDir.appendingPathComponent("board.json")
    }

    private init() { load() }

    // MARK: Order

    /// The flights in the order you put them, with any you have not placed
    /// yet at the front, newest first.
    func ordered(_ flights: [AssignedIssue], in repository: String) -> [AssignedIssue] {
        let saved = repos[repository]?.order ?? []
        let byNumber = Dictionary(flights.map { ($0.number, $0) }, uniquingKeysWith: { first, _ in first })
        let placed = saved.compactMap { byNumber[$0] }
        let placedNumbers = Set(placed.map(\.number))
        let fresh = flights
            .filter { !placedNumbers.contains($0.number) }
            .sorted { $0.number > $1.number }
        return fresh + placed
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

/// What a priority looks like: P1 is on fire, P5 can wait.
enum FlightPriority {
    static let all = [1, 2, 3, 4, 5]

    static func label(_ value: Int) -> String { "P\(value)" }

    /// Red at P1, cooling to blue at P5.
    static func color(_ value: Int) -> Color {
        switch value {
        case 1: Color(red: 0.91, green: 0.31, blue: 0.33)
        case 2: Color(red: 0.94, green: 0.55, blue: 0.24)
        case 3: Color(red: 0.90, green: 0.78, blue: 0.30)
        case 4: Color(red: 0.37, green: 0.75, blue: 0.62)
        default: Color(red: 0.38, green: 0.60, blue: 0.93)
        }
    }
}
