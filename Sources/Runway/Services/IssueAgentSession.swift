import CryptoKit
import Foundation

enum IssueAgentProvider: String, CaseIterable {
    case claude
    case gemini
}

/// Permanent provider conversation identities derived from immutable issue
/// identity. No UI state or title participates, so remove/re-add and renames
/// resolve to the same provider session.
enum IssueAgentSession {
    static func id(
        provider: IssueAgentProvider,
        repository: String?,
        issueNumber: Int?
    ) -> UUID? {
        guard let repository, !repository.isEmpty,
              let issueNumber else { return nil }
        return id(provider: provider, repository: repository, issueNumber: issueNumber)
    }

    static func id(
        provider: IssueAgentProvider,
        repository: String,
        issueNumber: Int
    ) -> UUID {
        DeterministicSessionID.uuid(for: [
            "runway-agent-session-v1",
            provider.rawValue,
            repository.lowercased(),
            String(issueNumber),
        ].joined(separator: ":"))
    }
}

enum DeterministicSessionID {
    static func uuid(for identity: String) -> UUID {
        var bytes = Array(SHA256.hash(data: Data(identity.utf8)).prefix(16))
        // Provider CLIs validate caller-assigned session IDs as UUIDv4. Keep the
        // payload deterministic while setting the required version and variant.
        bytes[6] = (bytes[6] & 0x0f) | 0x40
        bytes[8] = (bytes[8] & 0x3f) | 0x80
        let value: uuid_t = (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        )
        return UUID(uuid: value)
    }
}

/// The quick terminal's provider conversations: one per repository, rotated by a
/// per-repository generation counter so "start a new session" changes the id
/// permanently while old generations stay resumable by hand.
enum QuickTerminalSession {
    private static let generationsKey = "runway.quickSessionGenerations.v1"

    static func generation(for repository: String) -> Int {
        let saved = UserDefaults.standard.dictionary(forKey: generationsKey)
        return saved?[repository.lowercased()] as? Int ?? 0
    }

    static func bumpGeneration(for repository: String) {
        guard !repository.isEmpty else { return }
        var saved = UserDefaults.standard.dictionary(forKey: generationsKey) ?? [:]
        saved[repository.lowercased()] = generation(for: repository) + 1
        UserDefaults.standard.set(saved, forKey: generationsKey)
    }

    static func id(
        provider: IssueAgentProvider,
        repository: String,
        generation: Int? = nil
    ) -> UUID? {
        guard !repository.isEmpty else { return nil }
        return DeterministicSessionID.uuid(for: [
            "runway-quick-session-v1",
            provider.rawValue,
            repository.lowercased(),
            String(generation ?? self.generation(for: repository)),
        ].joined(separator: ":"))
    }
}
