import Foundation

/// Order for the repository picker.
///
/// The Focus board is what Runway is for, so the repositories whose boards moved
/// most recently come first: the list answers "what am I working on" instead of
/// "what did this list happen to look like the first time it was built".
/// Repositories with no board movement fall in behind, most recently selected
/// first, then alphabetically, so a clone that was never opened can never
/// outrank one being worked on.
enum RepositoryRanking {
    static func ranked(
        _ repositories: [String],
        focusMovement: [String: Date],
        recents: [String]
    ) -> [String] {
        let movement = Dictionary(
            focusMovement.map { ($0.key.lowercased(), $0.value) },
            uniquingKeysWith: { max($0, $1) }
        )
        var recentRank: [String: Int] = [:]
        for (index, repository) in recents.enumerated() {
            let key = repository.lowercased()
            if recentRank[key] == nil { recentRank[key] = index }
        }

        return repositories.enumerated()
            .sorted { a, b in
                let leftMoved = movement[a.element.lowercased()]
                let rightMoved = movement[b.element.lowercased()]

                // Board movement outranks everything else.
                if let leftMoved, let rightMoved, leftMoved != rightMoved {
                    return leftMoved > rightMoved
                }
                if (leftMoved == nil) != (rightMoved == nil) {
                    return leftMoved != nil
                }

                let leftRecent = recentRank[a.element.lowercased()] ?? Int.max
                let rightRecent = recentRank[b.element.lowercased()] ?? Int.max
                if leftRecent != rightRecent { return leftRecent < rightRecent }

                let order = a.element.localizedCaseInsensitiveCompare(b.element)
                if order != .orderedSame { return order == .orderedAscending }

                // Total order, so the sort cannot depend on input order.
                return a.offset < b.offset
            }
            .map(\.element)
    }
}
