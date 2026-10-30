import Foundation

/// The slides a walkthrough left for an issue.
///
/// Evidence is made outside Runway, as images in a folder named after the
/// issue. Runway only looks: it never writes there.
enum WalkthroughSlides {
    static let key = "runway.walkthroughRoot"

    static var root: URL {
        let saved = (UserDefaults.standard.string(forKey: key) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let resolved = FolderPath.resolved(saved) {
            return URL(fileURLWithPath: resolved)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Developer/walkthrough", isDirectory: true)
    }

    static func forIssue(_ number: Int?) -> [URL] {
        guard let number else { return [] }
        let folder = root.appendingPathComponent(String(number), isDirectory: true)
        let kinds = Set(["png", "jpg", "jpeg", "gif", "heic"])
        let files = (try? FileManager.default.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: nil
        )) ?? []
        return files
            .filter { kinds.contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }
}
