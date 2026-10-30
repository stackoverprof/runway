import Foundation

/// Order for the repository picker: most recently selected first, then
/// alphabetically, so a clone that was never opened can never outrank one
/// being read.
enum RepositoryRanking {
    static func ranked(
        _ repositories: [String],
        recents: [String]
    ) -> [String] {
        var recentRank: [String: Int] = [:]
        for (index, repository) in recents.enumerated() {
            let key = repository.lowercased()
            if recentRank[key] == nil { recentRank[key] = index }
        }

        return repositories.enumerated()
            .sorted { a, b in
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
