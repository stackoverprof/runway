import Foundation

/// A repository's Focus lanes. The selected board is a viewport, not the
/// lifetime of the other boards' terminals.
struct FocusBoards: Codable, Equatable {
    private(set) var boards: [[Int]]
    private(set) var selectedIndex: Int

    init(boards: [[Int]] = [[]], selectedIndex: Int = 0) {
        var seen = Set<Int>()
        self.boards = (boards.isEmpty ? [[]] : boards).map { board in
            var kept: [Int] = []
            for number in board where kept.count < 5 {
                if seen.insert(number).inserted { kept.append(number) }
            }
            return kept
        }
        self.selectedIndex = min(max(selectedIndex, 0), self.boards.count - 1)
    }

    private enum CodingKeys: String, CodingKey { case boards, selectedIndex }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            boards: try container.decode([[Int]].self, forKey: .boards),
            selectedIndex: try container.decode(Int.self, forKey: .selectedIndex)
        )
    }

    var selected: [Int] { boards[selectedIndex] }
    var all: [Int] { boards.flatMap { $0 } }
    var allSet: Set<Int> { Set(all) }
    var count: Int { boards.count }

    func boardIndex(containing issueNumber: Int) -> Int? {
        boards.firstIndex { $0.contains(issueNumber) }
    }

    mutating func select(_ index: Int) {
        guard boards.indices.contains(index) else { return }
        selectedIndex = index
    }

    mutating func create() {
        boards.append([])
        selectedIndex = boards.count - 1
    }

    mutating func replaceSelected(with numbers: [Int]) {
        var seen = Set(boards.enumerated()
            .filter { $0.offset != selectedIndex }
            .flatMap { $0.element })
        var kept: [Int] = []
        for number in numbers where kept.count < 5 {
            if seen.insert(number).inserted { kept.append(number) }
        }
        boards[selectedIndex] = kept
    }

    mutating func reconcile(available: Set<Int>) {
        var seen = Set<Int>()
        for index in boards.indices {
            var kept: [Int] = []
            for number in boards[index] where kept.count < 5 && available.contains(number) {
                if seen.insert(number).inserted { kept.append(number) }
            }
            boards[index] = kept
        }
    }
}
