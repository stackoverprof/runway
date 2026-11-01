import AppKit
import Foundation
import Observation

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

    static let kinds = Set(["png", "jpg", "jpeg", "gif", "heic"])

    /// Read the folder. This touches the disk, so a view asks
    /// ``WalkthroughFolders`` instead, which remembers the answer.
    static func scan(_ number: Int) -> [URL] {
        let folder = root.appendingPathComponent(String(number), isDirectory: true)
        let files = (try? FileManager.default.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: nil
        )) ?? []
        return files
            .filter { kinds.contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }

    @MainActor
    static func forIssue(_ number: Int?) -> [URL] {
        guard let number else { return [] }
        return WalkthroughFolders.slides(for: number)
    }
}


/// Which slides each issue has, remembered.
///
/// A flight with 34 crews asks this 35 times, and a SwiftUI pane asks on
/// every pass over its body, which is constantly. Reading 35 directories
/// each time is what made the Walkthrough tab hang. The answer is kept and
/// re-read at most every few seconds.
@MainActor
enum WalkthroughFolders {
    private struct Looked {
        var slides: [URL]
        var at: Date
    }

    private static var looked: [Int: Looked] = [:]
    /// Long enough that a pass over the pane is free, short enough that a
    /// slide saved while Runway is open turns up on its own.
    private static let stale: TimeInterval = 5

    static func slides(for number: Int) -> [URL] {
        if let kept = looked[number], Date().timeIntervalSince(kept.at) < Self.stale {
            return kept.slides
        }
        let slides = WalkthroughSlides.scan(number)
        if let kept = looked[number], kept.slides != slides {
            // The folder changed, so whatever was decoded from it is stale.
            SlideThumbnails.forget(kept.slides)
        }
        looked[number] = Looked(slides: slides, at: Date())
        return slides
    }

    /// Look again now, whatever the clock says.
    static func refresh() {
        looked.removeAll()
    }
}


/// Slide thumbnails, decoded small, off the main thread, and kept.
///
/// A walkthrough slide is 2184x2184, about 19MB once decoded. Decoding one
/// inside a view's body froze the pane for as long as the decode took, and
/// a flight with a folder per crew decoded dozens in a row on the first
/// pass. Each file is read once, at the size a thumbnail needs, on a
/// background queue; the view gets a placeholder until it lands.
///
/// Each thumbnail awaits its own image, so a slide arriving redraws one
/// square rather than the whole pane. Two hundred squares redrawing two
/// hundred times is the other half of the stall.
@MainActor
final class SlideThumbnails {
    static let shared = SlideThumbnails()

    private var ready: [String: NSImage] = [:]
    /// Insertion order, so the oldest goes first instead of dropping the lot.
    private var order: [String] = []
    private var loading: Set<String> = []
    /// Asked for but not started: a flight can put two hundred thumbnails on
    /// screen at once, and decoding all of them together is its own stall.
    private var waiting: [URL] = []
    private var queued: Set<String> = []
    private let side: CGFloat = 320
    /// A board's worth of slides will not fit in memory. A few flights' will.
    private let limit = 120
    /// Enough to keep the grid filling visibly, few enough to leave the
    /// machine to the terminals.
    private let atOnce = 4

    /// Whoever is waiting on a slide that has not been decoded yet.
    private var wanting: [String: [CheckedContinuation<NSImage?, Never>]] = [:]

    /// The thumbnail, as soon as there is one. Awaited from a view's `.task`,
    /// which also cancels it when the view scrolls away.
    func thumbnail(for slide: URL) async -> NSImage? {
        let key = slide.path
        if let kept = ready[key] { return kept }
        return await withCheckedContinuation { continuation in
            wanting[key, default: []].append(continuation)
            if !loading.contains(key), !queued.contains(key) {
                queued.insert(key)
                waiting.append(slide)
            }
            pump()
        }
    }

    private func deliver(_ key: String, _ image: NSImage?) {
        for continuation in wanting.removeValue(forKey: key) ?? [] {
            continuation.resume(returning: image)
        }
    }

    private func pump() {
        while loading.count < atOnce, !waiting.isEmpty {
            let slide = waiting.removeFirst()
            let key = slide.path
            queued.remove(key)
            guard ready[key] == nil, !loading.contains(key) else { continue }
            loading.insert(key)
            let side = self.side
            Task.detached(priority: .utility) {
                let decoded = Self.decode(slide, side: side)
                await MainActor.run {
                    self.loading.remove(key)
                    if let decoded {
                        self.ready[key] = decoded
                        self.order.append(key)
                        while self.order.count > self.limit {
                            let oldest = self.order.removeFirst()
                            self.ready.removeValue(forKey: oldest)
                        }
                    }
                    self.deliver(key, decoded)
                    self.pump()
                }
            }
        }
    }

    /// Drop what was decoded from files that have changed or gone.
    static func forget(_ slides: [URL]) {
        let keys = Set(slides.map(\.path))
        shared.ready = shared.ready.filter { !keys.contains($0.key) }
        shared.order.removeAll { keys.contains($0) }
        shared.waiting.removeAll { keys.contains($0.path) }
        shared.queued.subtract(keys)
        for key in keys { shared.deliver(key, nil) }
    }

    nonisolated private static func decode(_ slide: URL, side: CGFloat) -> NSImage? {
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
        return NSImage(cgImage: thumbnail, size: NSSize(width: side, height: side))
    }
}
