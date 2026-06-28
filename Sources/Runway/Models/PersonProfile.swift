import Foundation
import AppKit

/// Person profile: login → display name + image data.
struct PersonProfile: Codable, Identifiable {
    var id: String { login }
    let login: String
    var displayName: String
    var imageData: Data?
    
    init(login: String, displayName: String = "", imageData: Data? = nil) {
        self.login = login
        self.displayName = displayName.isEmpty ? login : displayName
        self.imageData = imageData
    }
}

/// Globally shared manager that stores, loads, and reactively broadcasts
/// display name and custom avatar updates.
@MainActor @Observable final class PersonProfileManager {
    static let shared = PersonProfileManager()

    var profiles: [PersonProfile] = []

    private init() {
        load()
    }

    func load() {
        if let data = UserDefaults.standard.data(forKey: SettingsKey.personProfiles),
           let decoded = try? JSONDecoder().decode([PersonProfile].self, from: data) {
            profiles = decoded
        }
    }

    func save() {
        if let encoded = try? JSONEncoder().encode(profiles) {
            UserDefaults.standard.set(encoded, forKey: SettingsKey.personProfiles)
        }
    }

    func displayName(for login: String) -> String {
        profiles.first { $0.login.lowercased() == login.lowercased() }?.displayName ?? login
    }

    func customImage(for login: String) -> NSImage? {
        guard let data = profiles.first(where: { $0.login.lowercased() == login.lowercased() })?.imageData else { return nil }
        return NSImage(data: data)
    }

    func updateProfile(_ profile: PersonProfile) {
        if let index = profiles.firstIndex(where: { $0.login == profile.login }) {
            profiles[index] = profile
        } else {
            profiles.append(profile)
        }
        save()
    }
}

