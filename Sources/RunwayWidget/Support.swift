import SwiftUI

/// The few settings the widget reads, with Runway's defaults.
enum SettingsKey {
    static let pollInterval  = "widget.pollInterval"   // seconds
    static let idleMinutes   = "widget.idleMinutes"
    static let officeHours   = "widget.officeHours"
    static let hideBots      = "widget.hideBots"
    static let fireThreshold = "widget.fireThreshold"
    static let personProfiles = "widget.personProfiles"
    /// Where to look for local clones (unused by the widget's UI, kept for the shared code).
    static func cloneSearch(in defaults: UserDefaults = .standard) -> (root: String, depth: Int) {
        (NSHomeDirectory() + "/Developer", 6)
    }

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            pollInterval: 45, idleMinutes: 30, officeHours: 6, hideBots: true, fireThreshold: 5,
        ])
    }
}

struct Chip: View {
    let text: String; let tint: Color
    init(_ text: String, tint: Color) { self.text = text; self.tint = tint }
    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .medium, design: .monospaced))
            .foregroundStyle(tint)
            .lineLimit(1)
            .padding(.horizontal, 7).padding(.vertical, 2.5)
            .background(RoundedRectangle(cornerRadius: 5).fill(tint.opacity(0.14)))
            .overlay(RoundedRectangle(cornerRadius: 5).stroke(tint.opacity(0.25), lineWidth: 1))
    }
}

enum PullTitle {
    /// A bracket tag like [MERGE AFTER WEEKEND] pulled out of the title.
    static func tagged(_ title: String) -> (tag: String?, title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("["), let close = trimmed.firstIndex(of: "]") else {
            return (nil, trimmed)
        }
        let tag = String(trimmed[trimmed.index(after: trimmed.startIndex)..<close])
        let rest = trimmed[trimmed.index(after: close)...].trimmingCharacters(in: .whitespaces)
        return (tag.uppercased(), rest.isEmpty ? trimmed : rest)
    }
}

/// One entry in a Pulls section: a lone PR, or a stack of PRs each based on
/// the branch of the one below, listed top first.
enum PRStackItem: Identifiable {
    case single(RepositoryPullRequest)
    case stack([RepositoryPullRequest])

    var id: Int { bottom.number }

    var pullRequests: [RepositoryPullRequest] {
        switch self {
        case .single(let pullRequest): [pullRequest]
        case .stack(let stack): stack
        }
    }

    /// The PR nearest the target branch, next to merge.
    var bottom: RepositoryPullRequest {
        switch self {
        case .single(let pullRequest): pullRequest
        case .stack(let stack): stack[stack.count - 1]
        }
    }

    /// Groups PRs whose base is another of these PRs' head. Each stack takes
    /// the place of its first PR in the list.
    static func items(_ pullRequests: [RepositoryPullRequest]) -> [PRStackItem] {
        let byHead = Dictionary(pullRequests.map { ($0.headRefName, $0) }, uniquingKeysWith: { first, _ in first })
        var children: [String: [RepositoryPullRequest]] = [:]
        for pullRequest in pullRequests where byHead[pullRequest.baseRefName] != nil {
            children[pullRequest.baseRefName, default: []].append(pullRequest)
        }
        var items: [PRStackItem] = []
        var placed: Set<Int> = []
        for pullRequest in pullRequests where !placed.contains(pullRequest.number) {
            var root = pullRequest
            var seen: Set<Int> = [root.number]
            while let parent = byHead[root.baseRefName], seen.insert(parent.number).inserted {
                root = parent
            }
            var chain: [RepositoryPullRequest] = []
            var queue = [root]
            while !queue.isEmpty {
                let next = queue.removeFirst()
                guard placed.insert(next.number).inserted else { continue }
                chain.append(next)
                queue += children[next.headRefName] ?? []
            }
            items.append(chain.count > 1 ? .stack(chain.reversed()) : .single(root))
        }
        return items
    }
}


enum Runway {
    static let green = Color(red: 0.18, green: 0.78, blue: 0.38)
    static let amber = Color(red: 0.94, green: 0.62, blue: 0.20)
    static let purple = Color(red: 0.64, green: 0.42, blue: 0.94)
    static let teal = Color(red: 0.45, green: 0.82, blue: 0.78)
}
