import AppKit
import CoreText
import SwiftUI

/// The board's own typeface.
///
/// JetBrains Mono, four weights, carried inside the app rather than installed
/// on the machine or pulled from Google Fonts: Runway ships as a bundle and
/// has to look the same on a laptop that has never seen the font and on one
/// with no network. The files are OFL licensed and the licence travels with
/// them.
///
/// Registration is private to the process, so nothing is added to the user's
/// font book. If a file is missing or will not register, every call falls
/// back to the system monospace and the view still draws.
@MainActor
enum RunwayFont {
    static let family = "JetBrains Mono"

    private static var registered = false

    /// Called once at launch, before the first view asks for a font.
    static func register() {
        guard !registered else { return }
        registered = true
        let names = [
            "JetBrainsMono-Regular",
            "JetBrainsMono-Medium",
            "JetBrainsMono-SemiBold",
            "JetBrainsMono-Bold",
        ]
        for name in names {
            guard let url = Bundle.module.url(
                forResource: name,
                withExtension: "ttf",
                subdirectory: "fonts"
            ) ?? Bundle.module.url(forResource: name, withExtension: "ttf") else { continue }
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
        available = NSFontManager.shared.availableFontFamilies.contains(family)
    }

    /// False when the files could not be registered, which is the signal to
    /// use the system monospace instead of drawing in the wrong face.
    private(set) static var available = false

    /// The face at a size and weight, or the system monospace if the family
    /// is not there.
    static func font(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        guard available else { return .system(size: size, weight: weight, design: .monospaced) }
        return .custom(family, fixedSize: size).weight(weight)
    }
}

extension Font {
    /// `Font.mono(11.5, .medium)`: the board's face at a fixed size, never
    /// scaled by the user's text setting, because the rows are laid out in
    /// points.
    @MainActor
    static func mono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        RunwayFont.font(size, weight)
    }
}
