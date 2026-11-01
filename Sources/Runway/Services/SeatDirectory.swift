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

    /// `git worktree list`, remembered. A pane asks this for every crew it
    /// draws, and a flight has dozens.
    private static var looked: [String: (at: Date, trees: [Worktree])] = [:]
    private static var scanning: Set<String> = []
    private static let stale: TimeInterval = 30

    /// What is known right now, and nothing slower than a dictionary read.
    ///
    /// Running git here was a crash, not just a stall: starting a process
    /// pumps the main runloop, SwiftUI's observer fires, and a second update
    /// pass begins inside the first. AttributeGraph calls that "setting value
    /// during update" and aborts. Nothing in a view's body may launch a
    /// process, so the answer is read from the cache and the cache is filled
    /// somewhere else.
    static func worktrees(from checkout: String) -> [Worktree] {
        let kept = looked[checkout]
        if kept == nil || Date().timeIntervalSince(kept!.at) > stale {
            scan(checkout)
        }
        return kept?.trees ?? []
    }

    /// Fill the cache off the main thread. Safe to call from anywhere,
    /// including a view: it starts a task and returns.
    static func scan(_ checkout: String) {
        guard !scanning.contains(checkout) else { return }
        scanning.insert(checkout)
        Task.detached(priority: .utility) {
            let trees = read(checkout)
            await MainActor.run {
                scanning.remove(checkout)
                let before = looked[checkout]?.trees.map(\.path) ?? []
                looked[checkout] = (Date(), trees)
                // A seat's folder is decided when its terminal config is
                // built and then kept, so a worktree that turns up after
                // that has to invalidate the config or it is never used.
                if before != trees.map(\.path) {
                    FlightCrewSessions.forgetConfigs()
                }
            }
        }
    }

    /// Prime every repository Runway knows before anything asks.
    static func prime(_ checkout: String?) {
        guard let checkout else { return }
        scan(checkout)
    }

    nonisolated private static func read(_ checkout: String) -> [Worktree] {
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
        return trees
    }

    /// Look again now: a crew that has just made its worktree should land in
    /// it the next time its terminal opens, not half a minute later.
    static func refresh() {
        looked.removeAll()
    }
}
