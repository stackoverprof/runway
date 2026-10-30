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
    static func sessionName(rank: AgentRank, repository: String, issue: Int) -> String {
        let clone = repository.split(separator: "/").last.map(String.init) ?? repository
        switch rank {
        case .atc: return "atc"
        case .pilot: return "\(clone)-\(issue)-pilot"
        case .copilot: return "\(clone)-\(issue)-copilot"
        case .crew: return "\(clone)-\(issue)"
        }
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
        env["RUNWAY_SESSION_NAME"] = sessionName(rank: rank, repository: repository, issue: issue)
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
