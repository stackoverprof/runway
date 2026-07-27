import AppKit
import Foundation

@MainActor
enum BrandingManager {
    private static var cachedLogo: (filename: String, image: NSImage)?

    private static var directory: URL {
        let url = AgentControl.supportDir.appendingPathComponent("branding", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func image(named filename: String) -> NSImage? {
        guard !filename.isEmpty else { return nil }
        if cachedLogo?.filename == filename { return cachedLogo?.image }
        guard let image = NSImage(contentsOf: logoURL(for: filename)), image.isValid else { return nil }
        cachedLogo = (filename, image)
        return image
    }

    static func importLogo(from sourceURL: URL, replacing previousFilename: String) throws -> String {
        let accessed = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if accessed { sourceURL.stopAccessingSecurityScopedResource() }
        }

        guard let image = NSImage(contentsOf: sourceURL), image.isValid else {
            throw BrandingError.invalidImage
        }

        let ext = sourceURL.pathExtension.lowercased()
        let suffix = ext.isEmpty ? "" : ".\(ext)"
        let filename = "logo-\(UUID().uuidString)\(suffix)"
        let destination = logoURL(for: filename)
        try FileManager.default.copyItem(at: sourceURL, to: destination)
        guard let storedImage = NSImage(contentsOf: destination), storedImage.isValid else {
            try? FileManager.default.removeItem(at: destination)
            throw BrandingError.invalidImage
        }

        if !previousFilename.isEmpty {
            try? FileManager.default.removeItem(at: logoURL(for: previousFilename))
        }
        cachedLogo = (filename, storedImage)
        return filename
    }

    static func removeLogo(named filename: String) {
        if !filename.isEmpty {
            try? FileManager.default.removeItem(at: logoURL(for: filename))
        }
        cachedLogo = nil
    }

    private static func logoURL(for filename: String) -> URL {
        directory.appendingPathComponent(URL(fileURLWithPath: filename).lastPathComponent)
    }
}

private enum BrandingError: LocalizedError {
    case invalidImage

    var errorDescription: String? {
        "Runway could not open that image."
    }
}
