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

/// The quick terminal's conversation identity. One conversation is kept until
/// the user asks for a new one, so quitting and reopening Runway lands back in
/// the same agent session. The stored root is random rather than derived from
/// anything on screen: nothing but the "new session" button can change it.
enum QuickTerminalSession {
    static let rootKey = "runway.quickSessionRoot.v1"

    /// Reads the stored root, minting and saving one on first use.
    static func root(in defaults: UserDefaults = .standard) -> String {
        if let saved = defaults.string(forKey: rootKey), !saved.isEmpty { return saved }
        let fresh = UUID().uuidString.lowercased()
        defaults.set(fresh, forKey: rootKey)
        return fresh
    }

    /// Abandon the current conversation. The next shell binds a brand-new id,
    /// and the previous one stays resumable by hand.
    @discardableResult
    static func rotate(in defaults: UserDefaults = .standard) -> String {
        let fresh = UUID().uuidString.lowercased()
        defaults.set(fresh, forKey: rootKey)
        return fresh
    }

    /// Each provider gets its own conversation off the same root, so switching
    /// the configured agent does not hand claude's id to gemini.
    static func id(provider: IssueAgentProvider, root: String) -> UUID {
        DeterministicSessionID.uuid(for: [
            "runway-quick-session-v2",
            provider.rawValue,
            root,
        ].joined(separator: ":"))
    }

    static func id(
        provider: IssueAgentProvider,
        in defaults: UserDefaults = .standard
    ) -> UUID {
        id(provider: provider, root: root(in: defaults))
    }
}
