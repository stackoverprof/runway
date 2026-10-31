import AppKit
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


/// Slide thumbnails, decoded small and kept.
///
/// A walkthrough slide is 2184x2184, about 19MB once decoded. Reading one
/// straight into an `NSImage` inside a view's body meant decoding every
/// slide again on every pass over the pane, which the panes do constantly,
/// and the app grew until the system took it away. Each file is read once,
/// at the size a thumbnail actually needs.
@MainActor
enum SlideThumbnails {
    private static var cache: [String: NSImage] = [:]
    private static let side: CGFloat = 320

    static func image(for slide: URL) -> NSImage? {
        let modified = (try? FileManager.default
            .attributesOfItem(atPath: slide.path)[.modificationDate] as? Date) ?? nil
        let key = "\(slide.path)|\(modified?.timeIntervalSince1970 ?? 0)"
        if let kept = cache[key] { return kept }
        guard let source = CGImageSourceCreateWithURL(slide as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: side * 2,
        ]
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(
            source, 0, options as CFDictionary
        ) else { return nil }
        let image = NSImage(
            cgImage: thumbnail,
            size: NSSize(width: side, height: side)
        )
        // One flight's worth is plenty; a board's worth is not.
        if cache.count > 40 { cache.removeAll() }
        cache[key] = image
        return image
    }
}
