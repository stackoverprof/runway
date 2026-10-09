import SwiftUI
import AppKit
import CryptoKit

/// The pure rules behind avatar fetching: what counts as a good response, how
/// long to wait between attempts, and where a photo lives on disk.
enum AvatarFetchPolicy {
    /// Waits between attempts of one fetch (so up to four tries, ~14s total).
    static let retryDelays: [Duration] = [.seconds(1), .seconds(3), .seconds(10)]
    /// Waits before a row that still shows initials asks again; then it gives up
    /// until the row is rebuilt.
    static let revisitDelays: [Duration] = [.seconds(60), .seconds(300)]

    static func acceptsStatus(_ status: Int?) -> Bool {
        guard let status else { return true } // non-HTTP (file://) responses
        return (200..<300).contains(status)
    }

    /// The image a response carries, or nil for an error page, rate-limit body,
    /// or anything else that is not a decodable picture.
    static func image(from data: Data, status: Int?) -> NSImage? {
        guard acceptsStatus(status), !data.isEmpty,
              let img = NSImage(data: data), img.isValid,
              img.size.width > 0, img.size.height > 0 else { return nil }
        return img
    }

    /// Stable, filesystem-safe name for a URL's cached bytes.
    static func diskFileName(for url: String) -> String {
        SHA256.hash(data: Data(url.utf8)).map { String(format: "%02x", $0) }.joined() + ".img"
    }
}

/// Caches decoded avatars by URL so the same person's photo is fetched once and
/// reused across every row (AsyncImage re-fetches per appearance, which made
/// repeated/identical avatars intermittently fall back to initials).
///
/// The last good bytes also go to disk, so a known face survives NSCache
/// eviction, a failed refetch, or an app restart instead of reverting to
/// initials. Concurrent loads of one URL share a single in-flight fetch.
@MainActor final class AvatarCache {
    static let shared = AvatarCache()
    private let cache = NSCache<NSString, NSImage>()
    private var inFlight: [String: Task<Data?, Never>] = [:]
    /// Disk hits refreshed from the network this session (once each).
    private var refreshed: Set<String> = []
    private let diskDir: URL

    init(diskDir: URL = AgentControl.supportDir.appendingPathComponent("avatars", isDirectory: true)) {
        self.diskDir = diskDir
        try? FileManager.default.createDirectory(at: diskDir, withIntermediateDirectories: true)
    }

    /// Memory hit, else the last good photo on disk (promoted into memory).
    func cached(_ url: String) -> NSImage? {
        if let img = cache.object(forKey: url as NSString) { return img }
        guard let data = try? Data(contentsOf: diskFile(url)),
              let img = AvatarFetchPolicy.image(from: data, status: nil) else { return nil }
        cache.setObject(img, forKey: url as NSString)
        refreshInBackground(url)
        return img
    }

    func load(_ url: String) async -> NSImage? {
        if let img = cached(url) { return img }
        guard await fetch(url) != nil else { return nil }
        return cache.object(forKey: url as NSString)
    }

    private func diskFile(_ url: String) -> URL {
        diskDir.appendingPathComponent(AvatarFetchPolicy.diskFileName(for: url))
    }

    /// Re-fetches a disk hit once per session so a changed photo eventually
    /// shows; a failure leaves the cached face in place.
    private func refreshInBackground(_ url: String) {
        guard !refreshed.contains(url) else { return }
        refreshed.insert(url)
        Task { _ = await fetch(url) }
    }

    /// One shared fetch per URL; good bytes land in memory and on disk.
    private func fetch(_ url: String) async -> Data? {
        if let running = inFlight[url] { return await running.value }
        guard let u = URL(string: url) else { return nil }
        let task = Task<Data?, Never> { await Self.download(u) }
        inFlight[url] = task
        let data = await task.value
        inFlight[url] = nil
        if let data, let img = AvatarFetchPolicy.image(from: data, status: nil) {
            cache.setObject(img, forKey: url as NSString)
            try? data.write(to: diskFile(url), options: .atomic)
        }
        return data
    }

    /// Tries once plus once per retry delay; nil when every attempt failed or
    /// the task was cancelled.
    nonisolated private static func download(_ url: URL) async -> Data? {
        for attempt in 0...AvatarFetchPolicy.retryDelays.count {
            if attempt > 0 {
                do { try await Task.sleep(for: AvatarFetchPolicy.retryDelays[attempt - 1]) } catch { return nil }
            }
            if Task.isCancelled { return nil }
            guard let (data, response) = try? await URLSession.shared.data(from: url) else { continue }
            let status = (response as? HTTPURLResponse)?.statusCode
            if AvatarFetchPolicy.image(from: data, status: status) != nil { return data }
        }
        return nil
    }
}

struct Avatar: View {
    let login: String
    var url: String? = nil
    let size: CGFloat
    @State private var loadedAvatar: LoadedAvatar?

    private struct LoadedAvatar {
        let login: String
        let url: String
        let image: NSImage
    }

    private var customImage: NSImage? {
        PersonProfileManager.shared.customImage(for: login)
    }

    private var loadTaskID: String {
        "\(login.lowercased())\u{0}\(url ?? "")\u{0}\(customImage == nil)"
    }

    var body: some View {
        Group {
            if let customImg = customImage {
                Image(nsImage: customImg).resizable().scaledToFill()
            } else if let loadedAvatar,
                      loadedAvatar.login == login.lowercased(),
                      loadedAvatar.url == url {
                Image(nsImage: loadedAvatar.image).resizable().scaledToFill()
            } else {
                initialsCircle
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .task(id: loadTaskID) {
            guard customImage == nil else { return }
            guard let url else { loadedAvatar = nil; return }
            if let hit = AvatarCache.shared.cached(url) {
                loadedAvatar = LoadedAvatar(login: login.lowercased(), url: url, image: hit)
                return
            }
            // A failed load is not final: revisit a couple of times so a blip
            // does not pin this row to initials until it is rebuilt.
            for wait in [nil] + AvatarFetchPolicy.revisitDelays.map(Optional.some) {
                if let wait {
                    do { try await Task.sleep(for: wait) } catch { return }
                }
                if let loaded = await AvatarCache.shared.load(url) {
                    guard !Task.isCancelled else { return }
                    loadedAvatar = LoadedAvatar(login: login.lowercased(), url: url, image: loaded)
                    return
                }
                if Task.isCancelled { return }
            }
        }
    }

    private var initialsCircle: some View {
        Circle()
            .fill(LinearGradient(colors: [color, color.opacity(0.7)], startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay(Text(initials).font(.system(size: size * 0.38, weight: .bold)).foregroundStyle(.white))
    }
    private var initials: String { String(login.prefix(2)).uppercased() }
    private var color: Color {
        let h = abs(login.hashValue)
        return Color(hue: Double(h % 360) / 360, saturation: 0.5, brightness: 0.65)
    }
}
