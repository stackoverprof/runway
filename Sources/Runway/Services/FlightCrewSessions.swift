import Foundation

/// Who runs where: the deterministic identity behind every agent Runway
/// starts, so the same seat always reopens the same conversation.
///
/// A pilot and its copilot answer for the flight, which is one issue. A crew
/// answers for one of that flight's sub-issues. The identity is derived, never
/// stored, so it survives a cache being thrown away.
@MainActor
enum FlightCrewSessions {
    static func boxID(rank: AgentRank, repository: String, issue: Int) -> UUID {
        DeterministicSessionID.uuid(
            for: "runway-v3-\(rank.rawValue)-v1:\(repository.lowercased()):\(issue)"
        )
    }

    /// What the session calls itself, and what other sessions address it by.
    ///
    /// A pilot takes the flight's own name, the part of its title before the
    /// colon, because that is what the work is called: `dependency`, not
    /// `monorepo-17345-pilot`. A crew keeps `<clone>-<issue>`, since an issue
    /// is what it answers for.
    static func sessionName(
        rank: AgentRank,
        repository: String,
        issue: Int,
        title: String = ""
    ) -> String {
        let clone = repository.split(separator: "/").last.map(String.init) ?? repository
        switch rank {
        case .atc: return "atc"
        case .pilot: return flightName(title) ?? "\(clone)-\(issue)"
        case .copilot: return (flightName(title) ?? "\(clone)-\(issue)") + "-copilot"
        case .crew: return "\(clone)-\(issue)"
        }
    }

    /// `Dependency: Keep the stack current` is flown by `dependency`.
    static func flightName(_ title: String) -> String? {
        let head = title.split(separator: ":", maxSplits: 1).first.map(String.init) ?? title
        let slug = head
            .lowercased()
            .map { $0.isLetter || $0.isNumber ? $0 : "-" }
            .reduce(into: "") { slug, character in
                if character == "-", slug.last == "-" { return }
                slug.append(character)
            }
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return slug.isEmpty ? nil : slug
    }

    /// The folder an agent starts in: the repository's main checkout. A crew
    /// makes its own worktrees from there, as the house rules tell it to.
    static func workingDirectory(for repository: String) -> String? {
        guard let path = GitHubFeed.shared.localPath(for: repository) else { return nil }
        return path
    }

    /// Everything that session needs to know about itself.
    static func environment(
        rank: AgentRank,
        repository: String,
        issue: Int,
        title: String,
        flight: Int?,
        reportsTo: String?
    ) -> [String: String] {
        let id = boxID(rank: rank, repository: repository, issue: issue)
        var env = AgentControl.environment(
            for: id,
            rank: rank,
            autorun: AgentControl.preferredAgentCommand(
                fallback: SettingsKey.configuredAgentCommand,
                focusRepository: repository,
                focusIssueNumber: issue
            ),
            focusRepository: repository,
            focusIssueNumber: issue,
            focusIssueTitle: title,
            focusCheckoutPath: workingDirectory(for: repository),
            issueAgentSessionsEnabled: true
        )
        let name = sessionName(rank: rank, repository: repository, issue: issue, title: title)
        env["RUNWAY_SESSION_NAME"] = name
        // What the session renames itself to, so a pilot reads as its flight.
        env["RUNWAY_AGENT_NAME"] = name
        if let flight { env["RUNWAY_FLIGHT"] = String(flight) }
        if rank == .crew { env["RUNWAY_CREW"] = String(issue) }
        if let reportsTo { env["RUNWAY_REPORTS_TO"] = reportsTo }
        env["RUNWAY_ROLE_CARD"] = RoleCard.write(
            rank: rank,
            repository: repository,
            issue: issue,
            title: title,
            flight: flight,
            reportsTo: reportsTo
        ).path
        return env
    }

    static func config(
        rank: AgentRank,
        repository: String,
        issue: Int,
        title: String,
        flight: Int?,
        reportsTo: String?
    ) -> TerminalConfig {
        TerminalConfig(
            workingDirectory: workingDirectory(for: repository),
            environment: environment(
                rank: rank,
                repository: repository,
                issue: issue,
                title: title,
                flight: flight,
                reportsTo: reportsTo
            )
        )
    }
}
