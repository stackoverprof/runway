import AppKit
import Foundation

/// The terminal typeface, and which candidates this Mac can actually render.
///
/// Ghostty silently falls back when it cannot find a family, so Settings only
/// offers faces that resolve here. Anything else the user wants can still be
/// typed in by hand.
enum TerminalFont {
    static let defaultFamily = "SF Mono"
    static let defaultSize = 9
    static let sizeRange = 8...24

    /// Coding faces worth putting at the top of the list, most reachable first:
    /// the four that ship with macOS, then the ones people install on purpose.
    /// Presence is checked at display time, so an uninstalled face costs nothing.
    static let popular = [
        "SF Mono",
        "Menlo",
        "Monaco",
        "Andale Mono",
        "JetBrains Mono",
        "Fira Code",
        "Cascadia Code",
        "Cascadia Mono",
        "IBM Plex Mono",
        "Source Code Pro",
        "Hack",
        "Inconsolata",
        "Iosevka",
        "Iosevka Term",
        "Victor Mono",
        "Geist Mono",
        "Roboto Mono",
        "Ubuntu Mono",
        "Space Mono",
        "Anonymous Pro",
        "DejaVu Sans Mono",
        "Liberation Mono",
        "Monaspace Neon",
        "Monaspace Argon",
        "Monaspace Xenon",
        "Monaspace Radon",
        "Monaspace Krypton",
        "Maple Mono",
        "Departure Mono",
        "Recursive Mono",
        "Berkeley Mono",
        "MonoLisa",
        "Comic Code",
        "Operator Mono",
        "PragmataPro",
        "Courier New",
    ]

    // MARK: Stored preference

    static var configuredFamily: String {
        sanitizedFamily(UserDefaults.standard.string(forKey: SettingsKey.terminalFontFamily))
    }

    static var configuredSize: Int {
        let stored = UserDefaults.standard.integer(forKey: SettingsKey.terminalFontSize)
        return clampedSize(stored == 0 ? defaultSize : stored)
    }

    /// A family name safe to write into the theme file: one line, trimmed, and
    /// never empty. A `#` would comment out the rest of the line.
    static func sanitizedFamily(_ family: String?) -> String {
        let cleaned = (family ?? "")
            .components(separatedBy: .newlines)
            .first?
            .replacingOccurrences(of: "#", with: " ")
            .trimmingCharacters(in: .whitespaces) ?? ""
        return cleaned.isEmpty ? defaultFamily : cleaned
    }

    static func clampedSize(_ size: Int) -> Int {
        min(max(size, sizeRange.lowerBound), sizeRange.upperBound)
    }

    // MARK: What this Mac can render

    /// Whether the family resolves to a real face. `SF Mono` is not published as
    /// a family on every macOS release even though it is installed, so the
    /// system's own monospaced face answers for it.
    static func isInstalled(_ family: String) -> Bool {
        if NSFont(name: family, size: 12) != nil { return true }
        return family == defaultFamily
    }

    /// The popular faces present on this Mac, keeping the curated order.
    static func installedPopular() -> [String] {
        popular.filter(isInstalled)
    }

    /// Every other fixed-pitch family installed, alphabetically. `.SF` and other
    /// dot-prefixed system aliases are skipped: they are not selectable names.
    static func installedOther() -> [String] {
        let known = Set(installedPopular())
        return NSFontManager.shared.availableFontFamilies
            .filter { family in
                !family.hasPrefix(".")
                    && !known.contains(family)
                    && NSFont(name: family, size: 12)?.isFixedPitch == true
            }
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    /// Everything Settings offers, with the current choice guaranteed present so
    /// a hand-typed or uninstalled family never disappears from the picker.
    static func selectableFamilies(current: String) -> [String] {
        var families = installedPopular() + installedOther()
        if !families.contains(current) { families.insert(current, at: 0) }
        return families
    }
}
