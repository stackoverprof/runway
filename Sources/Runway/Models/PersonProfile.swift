import Foundation
import AppKit

/// A repository identity plus the user's local presentation overrides.
struct PersonProfile: Codable, Identifiable, Sendable {
    var id: String { login }
    let login: String
    var displayName: String
    var githubFullName: String?
    var fullNameOverride: String?
    var avatarURL: String?
    var imageData: Data?

    var effectiveUsername: String {
        let local = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        return local.isEmpty ? login : local
    }

    var effectiveFullName: String {
        if let fullNameOverride {
            let local = fullNameOverride.trimmingCharacters(in: .whitespacesAndNewlines)
            return local.isEmpty ? effectiveUsername : local
        }
        let github = githubFullName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return github.isEmpty ? effectiveUsername : github
    }

    var effectiveDisplayName: String {
        effectiveFullName
    }

    init(
        login: String,
        displayName: String = "",
        githubFullName: String? = nil,
        fullNameOverride: String? = nil,
        avatarURL: String? = nil,
        imageData: Data? = nil
    ) {
        self.login = login
        self.displayName = displayName
        self.githubFullName = githubFullName
        self.fullNameOverride = fullNameOverride
        self.avatarURL = avatarURL
        self.imageData = imageData
    }
}

/// Globally shared manager that stores, loads, and reactively broadcasts
/// display name and custom avatar updates.
@MainActor @Observable final class PersonProfileManager {
    static let shared = PersonProfileManager()

    var profiles: [PersonProfile] = []
    private(set) var revision = 0
    
    // In-memory cache of decoded NSImage objects to avoid expensive decoding in body
    private var imageCache: [String: NSImage] = [:]
    @ObservationIgnored private var saveTask: Task<Void, Never>?

    private init() {
        load()
    }

    func load() {
        if let data = UserDefaults.standard.data(forKey: SettingsKey.personProfiles),
           let decoded = try? JSONDecoder().decode([PersonProfile].self, from: data) {
            profiles = decoded
            revision += 1
        }
    }

    func save() {
        saveTask?.cancel()
        let snapshot = profiles
        saveTask = Task {
            do {
                try await Task.sleep(for: .milliseconds(150))
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            let encoded = await Task.detached(priority: .utility) {
                try? JSONEncoder().encode(snapshot)
            }.value
            guard !Task.isCancelled, let encoded else { return }
            UserDefaults.standard.set(encoded, forKey: SettingsKey.personProfiles)
        }
    }

    func displayName(for login: String) -> String {
        fullName(for: login)
    }

    func username(for login: String) -> String {
        profile(for: login)?.effectiveUsername ?? login
    }

    func fullName(for login: String) -> String {
        profile(for: login)?.effectiveFullName ?? login
    }

    func profile(for login: String) -> PersonProfile? {
        let key = login.lowercased()
        return profiles.first { $0.login.lowercased() == key }
    }

    func discover(
        login: String,
        githubFullName: String? = nil,
        avatarURL: String? = nil
    ) {
        discover([(login: login, githubFullName: githubFullName, avatarURL: avatarURL)])
    }

    func discover(
        _ identities: [(login: String, githubFullName: String?, avatarURL: String?)]
    ) {
        var changed = false
        for identity in identities {
            let login = identity.login.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !login.isEmpty else { continue }
            let key = login.lowercased()
            let githubName = identity.githubFullName?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let remoteAvatar = identity.avatarURL?
                .trimmingCharacters(in: .whitespacesAndNewlines)

            if let index = profiles.firstIndex(where: { $0.login.lowercased() == key }) {
                if profiles[index].displayName.lowercased() == key,
                   profiles[index].githubFullName == nil {
                    profiles[index].displayName = ""
                    changed = true
                }
                if let githubName, !githubName.isEmpty,
                   profiles[index].githubFullName != githubName {
                    profiles[index].githubFullName = githubName
                    changed = true
                }
                if profiles[index].avatarURL == nil, let remoteAvatar, !remoteAvatar.isEmpty {
                    profiles[index].avatarURL = remoteAvatar
                    changed = true
                }
            } else {
                profiles.append(PersonProfile(
                    login: login,
                    githubFullName: githubName,
                    avatarURL: remoteAvatar
                ))
                changed = true
            }
        }
        if changed {
            revision += 1
            save()
        }
    }

    func customImage(for login: String) -> NSImage? {
        let key = login.lowercased()
        if let cached = imageCache[key] { return cached }
        
        guard let data = profiles.first(where: { $0.login.lowercased() == key })?.imageData else { return nil }
        if let image = NSImage(data: data) {
            imageCache[key] = image
            return image
        }
        return nil
    }

    func updateProfile(_ profile: PersonProfile) {
        let key = profile.login.lowercased()
        imageCache.removeValue(forKey: key) // Invalidate cached image
        
        if let index = profiles.firstIndex(where: {
            $0.login.lowercased() == profile.login.lowercased()
        }) {
            profiles[index] = profile
        } else {
            profiles.append(profile)
        }
        revision += 1
        save()
    }
}
