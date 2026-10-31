import Foundation

/// The evidence toolkit, installed where an agent can reach it.
///
/// Slides used to come from a skill on Erbin's machine. They are part of the
/// work, not part of his shell, so the renderer, the templates and the guide
/// ride inside Runway and are laid down beside the other agent helpers. Any
/// seat can make a walkthrough; nothing has to be installed first.
@MainActor
enum Walkthrough {
    static var toolkit: URL {
        RunwayStorage.supportDir.appendingPathComponent("walkthrough", isDirectory: true)
    }

    /// Where the rendered slides land, one folder per issue.
    static var output: URL {
        let saved = UserDefaults.standard.string(forKey: WalkthroughSlides.key) ?? ""
        if !saved.isEmpty { return URL(fileURLWithPath: saved) }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Developer/walkthrough", isDirectory: true)
    }

    /// Copy the toolkit out of the bundle on every launch, so an updated
    /// Runway brings an updated renderer with it.
    static func install() {
        guard let bundled = Bundle.module.url(
            forResource: "walkthrough",
            withExtension: nil
        ) else { return }
        let destination = toolkit
        try? FileManager.default.createDirectory(
            at: RunwayStorage.supportDir,
            withIntermediateDirectories: true
        )
        try? FileManager.default.removeItem(at: destination)
        try? FileManager.default.copyItem(at: bundled, to: destination)
        for script in ["publish-to-issue.sh", "reveal.sh"] {
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o755],
                ofItemAtPath: destination.appendingPathComponent(script).path
            )
        }
    }
}
