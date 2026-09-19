import Foundation

/// Finds the resumable conversation id behind a terminal, so a box can hand back
/// a command that reopens the same agent conversation anywhere else.
///
/// Three sources, most trustworthy first:
/// 1. the id a Runway-scoped wrapper recorded for this box,
/// 2. the deterministic id an issue-owned box is bound to,
/// 3. the newest transcript the provider itself wrote for this directory.
enum AgentSessionLocator {
    struct Resolved: Equatable {
        let provider: IssueAgentProvider
        let sessionID: String

        /// The whole command, which is what gets pasted into another terminal.
        var resumeCommand: String { provider.resumeCommand(sessionID: sessionID) }
    }

    // MARK: Recorded by the wrapper

    /// Parse `{"provider":"claude","sessionId":"…"}` as written by the scoped
    /// wrapper scripts.
    static func recorded(in contents: String) -> Resolved? {
        guard let data = contents.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let sessionID = (json["sessionId"] as? String)?
                  .trimmingCharacters(in: .whitespacesAndNewlines),
              !sessionID.isEmpty else { return nil }
        let provider = (json["provider"] as? String)
            .flatMap(IssueAgentProvider.init(rawValue:)) ?? .claude
        return Resolved(provider: provider, sessionID: sessionID)
    }

    static func recorded(for boxID: UUID) -> Resolved? {
        guard let contents = try? String(
            contentsOf: AgentControl.sessionFile(for: boxID),
            encoding: .utf8
        ) else { return nil }
        return recorded(in: contents)
    }

    // MARK: Provider transcripts on disk

    /// Claude Code files transcripts under a directory named after the project
    /// path with the separators flattened. The exact substitution has changed
    /// over releases, so compare both sides through the same normalization
    /// instead of trying to reproduce it.
    static func normalizedProjectKey(_ path: String) -> String {
        let scalars = path.lowercased().unicodeScalars.map { scalar -> Character in
            let isAlphanumeric = (scalar >= "a" && scalar <= "z")
                || (scalar >= "0" && scalar <= "9")
            return isAlphanumeric ? Character(scalar) : "-"
        }
        // Runs of separators collapse, so "/a//b/" and "-a-b-" agree.
        var out = ""
        var previousWasSeparator = false
        for character in scalars {
            if character == "-" {
                if !previousWasSeparator { out.append(character) }
                previousWasSeparator = true
            } else {
                out.append(character)
                previousWasSeparator = false
            }
        }
        return out.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }

    static var claudeProjectsDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/projects", isDirectory: true)
    }

    /// Newest Claude transcript for `directory`, which is the conversation that
    /// terminal is in (or was in last).
    static func latestClaudeSession(inDirectory directory: String) -> Resolved? {
        let fileManager = FileManager.default
        let wanted = normalizedProjectKey(directory)
        guard !wanted.isEmpty,
              let projects = try? fileManager.contentsOfDirectory(
                at: claudeProjectsDirectory,
                includingPropertiesForKeys: nil
              ) else { return nil }
        guard let project = projects.first(where: {
            normalizedProjectKey($0.lastPathComponent) == wanted
        }) else { return nil }

        guard let transcripts = try? fileManager.contentsOfDirectory(
            at: project,
            includingPropertiesForKeys: [.contentModificationDateKey]
        ) else { return nil }
        let newest = transcripts
            .filter { $0.pathExtension == "jsonl" }
            .max { lhs, rhs in
                let left = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]))?
                    .contentModificationDate ?? .distantPast
                let right = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]))?
                    .contentModificationDate ?? .distantPast
                return left < right
            }
        guard let newest else { return nil }
        return Resolved(
            provider: .claude,
            sessionID: newest.deletingPathExtension().lastPathComponent
        )
    }

    // MARK: Peer names

    /// Claude Code registers every live session here as `<pid>.json`, carrying
    /// the short peer name (`monorepo-77`) that `SendMessage` and `ListAgents`
    /// address it by. Nothing else publishes that mapping, so this directory is
    /// the only way to get from a transcript UUID to the name an agent answers to.
    static var claudeSessionsDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/sessions", isDirectory: true)
    }

    /// One registry entry, yielding its name only when the entry really is for
    /// `sessionID`. `updatedAt` comes back too so the caller can break ties.
    static func peerName(
        in contents: String,
        matching sessionID: String
    ) -> (name: String, updatedAt: Double)? {
        guard let data = contents.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let recorded = json["sessionId"] as? String,
              recorded.caseInsensitiveCompare(sessionID) == .orderedSame,
              let name = (json["name"] as? String)?
                  .trimmingCharacters(in: .whitespacesAndNewlines),
              !name.isEmpty else { return nil }
        return (name, (json["updatedAt"] as? Double) ?? 0)
    }

    /// The name this conversation answers to as a peer, if it is still running.
    /// Only Claude writes the registry, and only for a live session, so a `nil`
    /// here is the ordinary case for a finished or non-Claude terminal.
    static func peerName(for sessionID: String) -> String? {
        guard !sessionID.isEmpty,
              let entries = try? FileManager.default.contentsOfDirectory(
                  at: claudeSessionsDirectory,
                  includingPropertiesForKeys: nil
              ) else { return nil }
        // A session killed outright leaves its `<pid>.json` behind, and a resume
        // of the same conversation writes a second file under the new pid. Both
        // carry the same id, so take the freshest rather than whichever the
        // directory listing happened to return first.
        return entries
            .filter { $0.pathExtension == "json" }
            .compactMap { url in
                (try? String(contentsOf: url, encoding: .utf8))
                    .flatMap { peerName(in: $0, matching: sessionID) }
            }
            .max { $0.updatedAt < $1.updatedAt }?
            .name
    }

    // MARK: Resolution

    static func resolve(
        boxID: UUID,
        workingDirectory: String?,
        focusRepository: String?,
        focusIssueNumber: Int?,
        issueSessionsEnabled: Bool
    ) -> Resolved? {
        if let recorded = recorded(for: boxID) { return recorded }
        if issueSessionsEnabled,
           let recorded = AgentControl.durableSession(
               focusRepository: focusRepository,
               focusIssueNumber: focusIssueNumber
           ) {
            return recorded
        }
        if issueSessionsEnabled,
           let sessionID = IssueAgentSession.id(
               provider: .claude,
               repository: focusRepository,
               issueNumber: focusIssueNumber
           ) {
            return Resolved(
                provider: .claude,
                sessionID: sessionID.uuidString.lowercased()
            )
        }
        guard let workingDirectory, !workingDirectory.isEmpty else { return nil }
        return latestClaudeSession(inDirectory: workingDirectory)
    }
}
