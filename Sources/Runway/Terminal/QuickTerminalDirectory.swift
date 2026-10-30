import Foundation

/// Where the quick terminal's shell starts. A folder picked in Settings wins
/// over the directory the previous shell recorded, so the quick terminal always
/// opens where the user pointed it instead of wherever it was last left.
enum QuickTerminalDirectory {
    /// The raw, user-typed preference. Empty means "reopen the last directory".
    static var configured: String {
        UserDefaults.standard.string(forKey: SettingsKey.quickTerminalDirectory) ?? ""
    }

    /// Absolute path for the configured folder: `~` expanded, whitespace and
    /// trailing slashes trimmed. Nil when nothing is configured or the path is
    /// not a folder on this Mac, so callers fall back to the recorded cwd.
    static var startupPath: String? { resolved(configured) }

    static func resolved(
        _ raw: String,
        isDirectory: (String) -> Bool = directoryExists
    ) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        var path = (trimmed as NSString).expandingTildeInPath
        while path.count > 1, path.hasSuffix("/") { path.removeLast() }

        // Relative paths have no meaning for a shell Runway launches itself.
        guard path.hasPrefix("/"), isDirectory(path) else { return nil }
        return path
    }

    static func directoryExists(_ path: String) -> Bool {
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
        return exists && isDirectory.boolValue
    }
}
