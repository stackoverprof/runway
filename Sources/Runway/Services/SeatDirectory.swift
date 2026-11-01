import Foundation

/// Where each seat's terminal opens.
///
/// A pilot and a crew want different folders. The crew writes code for one
/// issue, so it belongs in that issue's worktree: the branch is already
/// checked out, `git status` means something, and nothing it builds can land
/// on the wrong branch. The pilot writes no code; it reads issues, briefs
/// crews and keeps a checklist, and it is the one seat that wants to see
/// every worktree at once, so it opens at the folder that holds them.
///
/// The layout is the usual one and nothing here is specific to a person:
/// a repository with worktrees is a container, `<repo>/main` beside
/// `<repo>/<slug>-<issue>`; a repository without them is a plain checkout at
/// `<repo>`. In the plain case the container and the checkout are the same
/// folder, so both seats open in the same place and nothing changes.
@MainActor
enum SeatDirectory {
    /// Turn off to start every seat in the main checkout, as Runway did
    /// before. Some tools want a git repository as the working directory,
    /// and a container folder is not one.
    static let perSeatKey = "runway.seatDirectories"

    static var perSeat: Bool {
        UserDefaults.standard.object(forKey: perSeatKey) as? Bool ?? true
    }

    static func path(rank: AgentRank, repository: String, issue: Int?) -> String? {
        guard let checkout = GitHubFeed.shared.localPath(for: repository) else { return nil }
        guard perSeat else { return checkout }
        switch rank {
        case .atc, .pilot, .copilot:
            return container(of: checkout)
        case .crew:
            guard let issue else { return checkout }
            return worktree(for: issue, from: checkout) ?? checkout
        }
    }

    /// The folder the checkouts of this repository sit in, which is the
    /// checkout itself when there are no worktrees.
    static func container(of checkout: String) -> String {
        CloneName.root(ofCheckout: checkout)
    }

    /// The worktree serving one issue, by the house rule that a branch and
    /// its worktree both end in `-<issue>`.
    ///
    /// Read from git rather than guessed from the folder name, so a worktree
    /// parked somewhere else still counts, and a stale folder does not.
    static func worktree(for issue: Int, from checkout: String) -> String? {
        for entry in worktrees(from: checkout) {
            guard entry.path != checkout else { continue }
            let folder = URL(fileURLWithPath: entry.path).lastPathComponent
            let suffix = "-\(issue)"
            if folder.hasSuffix(suffix) || (entry.branch?.hasSuffix(suffix) ?? false) {
                var isDirectory: ObjCBool = false
                guard FileManager.default.fileExists(atPath: entry.path, isDirectory: &isDirectory),
                      isDirectory.boolValue else { continue }
                return entry.path
            }
        }
        return nil
    }

    struct Worktree {
        let path: String
        let branch: String?
    }

    /// `git worktree list`, remembered briefly. A pane asks this for every
    /// crew it draws, and a flight has dozens.
    private static var looked: [String: (at: Date, trees: [Worktree])] = [:]
    private static let stale: TimeInterval = 10

    static func worktrees(from checkout: String) -> [Worktree] {
        if let kept = looked[checkout], Date().timeIntervalSince(kept.at) < stale {
            return kept.trees
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["git", "-C", checkout, "worktree", "list", "--porcelain"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        var trees: [Worktree] = []
        if (try? process.run()) != nil {
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            var path: String?
            var branch: String?
            for line in String(decoding: data, as: UTF8.self).split(
                separator: "\n", omittingEmptySubsequences: false
            ) {
                if line.hasPrefix("worktree ") {
                    if let path { trees.append(Worktree(path: path, branch: branch)) }
                    path = String(line.dropFirst("worktree ".count))
                    branch = nil
                } else if line.hasPrefix("branch ") {
                    branch = String(line.dropFirst("branch ".count))
                        .replacingOccurrences(of: "refs/heads/", with: "")
                }
            }
            if let path { trees.append(Worktree(path: path, branch: branch)) }
        }

        looked[checkout] = (Date(), trees)
        return trees
    }

    /// Look again now: a crew that has just made its worktree should land in
    /// it the next time its terminal opens, not ten seconds later.
    static func refresh() {
        looked.removeAll()
    }
}
