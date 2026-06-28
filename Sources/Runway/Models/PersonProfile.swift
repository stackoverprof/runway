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
    
    // In-memory cache of decoded NSImage objects to avoid expensive decoding in body
    private var imageCache: [String: NSImage] = [:]

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
        
        if let index = profiles.firstIndex(where: { $0.login == profile.login }) {
            profiles[index] = profile
        } else {
            profiles.append(profile)
        }
        save()
    }
}

