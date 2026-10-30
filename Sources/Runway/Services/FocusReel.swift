import Foundation

/// A repository's Focus lane: one ordered list, every issue of it on screen
/// with its own terminal. The lane scrolls when it outgrows its area, so the
/// list is never windowed and no issue is ever hidden from it.
struct FocusReel: Codable, Equatable {
    static let defaultLimit = 10
    static let limitRange = 1...50

    private(set) var issues: [Int]

    init(issues: [Int] = []) {
        self.issues = Self.deduplicated(issues)
    }

    // MARK: Persistence

    private enum CodingKeys: String, CodingKey {
        case issues
        // Paginated boards, the format before the reel.
        case boards, selectedIndex
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let issues = try container.decodeIfPresent([Int].self, forKey: .issues) {
            // A window offset from the versions that had one is simply dropped.
            self.init(issues: issues)
            return
        }
        let boards = try container.decode([[Int]].self, forKey: .boards)
        let selectedIndex = try container.decodeIfPresent(Int.self, forKey: .selectedIndex) ?? 0
        self = Self.migrating(boards: boards, selectedIndex: selectedIndex)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(issues, forKey: .issues)
    }

    /// Flattens paginated boards in board order, keeping the first copy of any
    /// duplicate and ignoring the Focus limit so nothing is lost.
    static func migrating(boards: [[Int]], selectedIndex: Int) -> FocusReel {
        var seen = Set<Int>()
        var flattened: [Int] = []
        for board in boards {
            for number in board where seen.insert(number).inserted {
                flattened.append(number)
            }
        }
        return FocusReel(issues: flattened)
    }

    // MARK: Membership

    var count: Int { issues.count }
    var allSet: Set<Int> { Set(issues) }

    func contains(_ issueNumber: Int) -> Bool { issues.contains(issueNumber) }

    /// Replaces the order. Never trims to the Focus limit: callers check the
    /// limit before adding, and an existing list over the limit stays intact.
    mutating func replace(with numbers: [Int]) {
        issues = Self.deduplicated(numbers)
    }

    mutating func reconcile(available: Set<Int>) {
        replace(with: issues.filter(available.contains))
    }

    /// Whether one more issue fits under `limit`. `nil` means unlimited. A list
    /// already over a lowered limit keeps its issues but takes no more.
    static func canAdd(count: Int, limit: Int?) -> Bool {
        guard let limit else { return true }
        return count < limit
    }

    private static func deduplicated(_ numbers: [Int]) -> [Int] {
        var seen = Set<Int>()
        return numbers.filter { seen.insert($0).inserted }
    }
}
