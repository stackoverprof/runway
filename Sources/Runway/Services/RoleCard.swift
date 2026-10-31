import Foundation

/// What an agent is told the moment it starts: who it is, what it answers
/// for, who it reports to, and the house rules of this Runway.
///
/// The card is written to disk per seat and named in the environment, so
/// `runway whoami` reads it back. Nothing here lives in a repository, and
/// nothing has to be shared for someone else's Runway to brief its own crew.
@MainActor
enum RoleCard {
    static func text(
        rank: AgentRank,
        repository: String,
        issue: Int,
        title: String,
        flight: Int?,
        reportsTo: String?
    ) -> String {
        var lines: [String] = []
        lines.append("You are the \(rank.label) in Runway.")
        lines.append("")

        switch rank {
        case .atc:
            lines.append("You sit above every flight and belong to none. You can order any")
            lines.append("pilot or crew, make a flight, and take work off one.")
            lines.append("Repository on screen: \(repository)")
        case .pilot, .copilot:
            lines.append("You fly \(GitHubNumber.reference(issue)): \(title)")
            lines.append("Repository: \(repository)")
            lines.append("Read it: gh issue view \(issue) --repo \(repository)")
            lines.append("Its crews are that issue's sub-issues. You own the order they fly in,")
            lines.append("what each waits on, and when one is done. You do not write the code:")
            lines.append("that is the crew's work.")
        case .crew:
            lines.append("You answer for \(GitHubNumber.reference(issue)): \(title)")
            lines.append("Repository: \(repository)")
            lines.append("Read it: gh issue view \(issue) --repo \(repository)")
            if let flight {
                lines.append("You are a crew of flight \(GitHubNumber.reference(flight)).")
            }
        }

        if let reportsTo {
            lines.append("You report to: \(reportsTo)")
        }
        lines.append("")
        lines.append("Your hands are the `runway` command. Run `runway help` for its verbs.")
        if rank != .atc {
            lines.append("`runway show` prints where this flight stands and what each crew is on.")
            lines.append("`runway progress` is the flight's checklist, and `runway tick <n>` marks a step done.")
        }
        lines.append("")
        lines.append("House rules")
        lines.append(HouseRules.current)
        return lines.joined(separator: "\n") + "\n"
    }

    @discardableResult
    static func write(
        rank: AgentRank,
        repository: String,
        issue: Int,
        title: String,
        flight: Int?,
        reportsTo: String?
    ) -> URL {
        let directory = RunwayStorage.supportDir.appendingPathComponent("roles", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let id = FlightCrewSessions.boxID(rank: rank, repository: repository, issue: issue)
        let file = directory.appendingPathComponent("\(id.uuidString).md")
        let card = text(
            rank: rank,
            repository: repository,
            issue: issue,
            title: title,
            flight: flight,
            reportsTo: reportsTo
        )
        try? card.data(using: .utf8)?.write(to: file)
        return file
    }
}

/// The rules every agent of this Runway works by. One place, held by the app,
/// never committed to a repository, editable in Settings.
enum HouseRules {
    static let key = "runway.houseRules"

    static let fallback = """
    - A branch is named <type>/<slug>-<issue>, the issue number last.
    - A pull request says "Part of #<issue>", never a closing keyword.
    - A crew works in its own worktree beside the main checkout, and removes it
      when its pull request merges.
    - A crew never closes its own issue: it reports, and the pilot or the user
      closes it.
    - Never force-push a shared branch, and never merge without a review.
    - Say what you did in plain words, with the numbers and links that prove it.
    """

    static var current: String {
        let saved = (UserDefaults.standard.string(forKey: key) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return saved.isEmpty ? fallback : saved
    }
}
