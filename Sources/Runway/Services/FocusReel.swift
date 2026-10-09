import Foundation

/// A repository's Focus lane: one ordered list seen through a sliding window.
/// Only the window's issues show their terminals in the right pane; the rest
/// keep their sessions running while hidden above or below it. Moving the
/// window never changes membership, so it is never a Focus entry or exit.
struct FocusReel: Codable, Equatable {
    static let defaultVisibleCount = 4
    static let visibleCountRange = 1...9
    static let defaultLimit = 10
    static let limitRange = 1...50

    private(set) var issues: [Int]
    private(set) var offset: Int
    /// How many cards the window shows. A display preference, so it is not
    /// persisted with the list; the owner applies the current setting.
    private(set) var visibleCount: Int

    init(issues: [Int] = [], offset: Int = 0, visibleCount: Int = FocusReel.defaultVisibleCount) {
        self.issues = Self.deduplicated(issues)
        self.offset = offset
        self.visibleCount = Self.clampedVisibleCount(visibleCount)
        clampOffset()
    }

    // MARK: Persistence

    private enum CodingKeys: String, CodingKey {
        case issues, offset
        // Paginated boards, the format before the reel.
        case boards, selectedIndex
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let issues = try container.decodeIfPresent([Int].self, forKey: .issues) {
            self.init(
                issues: issues,
                offset: try container.decodeIfPresent(Int.self, forKey: .offset) ?? 0
            )
            return
        }
        let boards = try container.decode([[Int]].self, forKey: .boards)
        let selectedIndex = try container.decodeIfPresent(Int.self, forKey: .selectedIndex) ?? 0
        self = Self.migrating(boards: boards, selectedIndex: selectedIndex)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(issues, forKey: .issues)
        try container.encode(offset, forKey: .offset)
    }

    /// Flattens paginated boards in board order, keeping the first copy of any
    /// duplicate and ignoring the Focus limit so nothing is lost. The window
    /// opens where the previously selected board began.
    static func migrating(boards: [[Int]], selectedIndex: Int) -> FocusReel {
        var seen = Set<Int>()
        var flattened: [Int] = []
        var selectedStart = 0
        for (index, board) in boards.enumerated() {
            if index == selectedIndex { selectedStart = flattened.count }
            for number in board where seen.insert(number).inserted {
                flattened.append(number)
            }
        }
        return FocusReel(issues: flattened, offset: selectedStart)
    }

    // MARK: Window

    var visible: [Int] {
        Array(issues.dropFirst(offset).prefix(visibleCount))
    }

    var hiddenAbove: Int { offset }
    var hiddenBelow: Int { max(0, issues.count - offset - visibleCount) }
    var count: Int { issues.count }
    var allSet: Set<Int> { Set(issues) }
    var firstHiddenBelow: Int? {
        hiddenBelow > 0 ? issues[offset + visibleCount] : nil
    }

    func contains(_ issueNumber: Int) -> Bool { issues.contains(issueNumber) }

    func isVisible(_ issueNumber: Int) -> Bool { visible.contains(issueNumber) }

    mutating func setVisibleCount(_ count: Int) {
        visibleCount = Self.clampedVisibleCount(count)
        clampOffset()
    }

    /// Slides the window by whole cards. Returns whether it moved.
    @discardableResult
    mutating func shift(by delta: Int) -> Bool {
        let previous = offset
        offset += delta
        clampOffset()
        return offset != previous
    }

    /// Slides the window just far enough to include the issue.
    @discardableResult
    mutating func reveal(_ issueNumber: Int) -> Bool {
        guard let index = issues.firstIndex(of: issueNumber) else { return false }
        let previous = offset
        if index < offset {
            offset = index
        } else if index >= offset + visibleCount {
            offset = index - visibleCount + 1
        }
        clampOffset()
        return offset != previous
    }

    /// Slides the window one card while a card is being dragged, carrying the
    /// dragged card to the edge it moved toward so it stays in the window and
    /// can be dropped into the spot that was hidden.
    @discardableResult
    mutating func shift(by delta: Int, carrying issueNumber: Int) -> Bool {
        guard delta != 0, issues.contains(issueNumber), shift(by: delta) else { return false }
        issues.removeAll { $0 == issueNumber }
        let index = delta < 0 ? offset : offset + visibleCount - 1
        issues.insert(issueNumber, at: min(max(index, 0), issues.endIndex))
        clampOffset()
        return true
    }

    // MARK: Membership

    /// Replaces the order. Never trims to the Focus limit: callers check the
    /// limit before adding, and an existing list over the limit stays intact.
    mutating func replace(with numbers: [Int]) {
        issues = Self.deduplicated(numbers)
        clampOffset()
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

    // MARK: Helpers

    private mutating func clampOffset() {
        offset = min(max(offset, 0), max(issues.count - visibleCount, 0))
    }

    private static func clampedVisibleCount(_ count: Int) -> Int {
        min(max(count, visibleCountRange.lowerBound), visibleCountRange.upperBound)
    }

    private static func deduplicated(_ numbers: [Int]) -> [Int] {
        var seen = Set<Int>()
        return numbers.filter { seen.insert($0).inserted }
    }
}

/// Turns scroll-wheel and trackpad input into whole-card window steps. The reel
/// never scrolls freely: a mouse notch is one card, a trackpad swipe steps once
/// per threshold of travel with a cooldown, and momentum is ignored so a flick
/// moves a card or two instead of flying through the list.
struct FocusReelScrollStepper {
    static let preciseThreshold: Double = 24
    static let preciseCooldown: TimeInterval = 0.16
    static let wheelCooldown: TimeInterval = 0.06

    private var accumulated: Double = 0
    private var lastStep: TimeInterval = -.infinity

    /// Returns -1 to reveal the card above, +1 for the card below, 0 for none.
    /// A positive `deltaY` (content moving down) reveals what is above, the
    /// same direction a scroll view would move.
    mutating func step(
        deltaY: Double,
        precise: Bool,
        isMomentum: Bool,
        gestureBegan: Bool,
        timestamp: TimeInterval
    ) -> Int {
        if isMomentum {
            accumulated = 0
            return 0
        }
        if gestureBegan { accumulated = 0 }
        guard deltaY != 0 else { return 0 }
        let direction = deltaY > 0 ? -1 : 1

        guard precise else {
            guard timestamp - lastStep >= Self.wheelCooldown else { return 0 }
            lastStep = timestamp
            return direction
        }

        if accumulated != 0, (accumulated > 0) != (deltaY > 0) { accumulated = 0 }
        accumulated += deltaY
        guard abs(accumulated) >= Self.preciseThreshold else { return 0 }
        guard timestamp - lastStep >= Self.preciseCooldown else {
            // Hold at the threshold so a continuing swipe steps again as soon
            // as the cooldown ends, without banking extra travel meanwhile.
            accumulated = accumulated > 0 ? Self.preciseThreshold : -Self.preciseThreshold
            return 0
        }
        lastStep = timestamp
        accumulated = 0
        return direction
    }
}
