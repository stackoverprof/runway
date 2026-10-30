import Foundation

/// Where this build keeps its files. A side-by-side build (an experimental
/// Runway installed next to the one you work in) names its own folder in
/// Info.plist, so the two never share caches or settings.
enum RunwayStorage {
    static let stateFolder: String = {
        let named = Bundle.main.object(forInfoDictionaryKey: "RunwayStateFolder") as? String
        let trimmed = named?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? "Runway" : trimmed
    }()

    static let supportDir: URL = {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let dir = base.appendingPathComponent(stateFolder, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()
}
