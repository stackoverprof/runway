import SwiftUI
import AppKit

/// Caches decoded avatars by URL so the same person's photo is fetched once and
/// reused across every row (AsyncImage re-fetches per appearance, which made
/// repeated/identical avatars intermittently fall back to initials).
@MainActor final class AvatarCache {
    static let shared = AvatarCache()
    private let cache = NSCache<NSString, NSImage>()

    func cached(_ url: String) -> NSImage? { cache.object(forKey: url as NSString) }

    func load(_ url: String) async -> NSImage? {
        if let img = cached(url) { return img }
        guard let u = URL(string: url) else { return nil }
        guard let (data, _) = try? await URLSession.shared.data(from: u),
              let img = NSImage(data: data) else { return nil }
        cache.setObject(img, forKey: url as NSString)
        return img
    }
}

struct Avatar: View {
    let login: String
    var url: String? = nil
    let size: CGFloat
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().scaledToFill()
            } else {
                initialsCircle
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .task(id: url) {
            guard let url else { image = nil; return }
            if let hit = AvatarCache.shared.cached(url) { image = hit; return }
            if let loaded = await AvatarCache.shared.load(url) { image = loaded }
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
