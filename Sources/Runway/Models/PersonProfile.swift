import Foundation

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
