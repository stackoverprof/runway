import Foundation
import SwiftUI

/// Gives the embedded terminals a neutral near-black theme that matches the card.
///
/// libghostty loads the user's real Ghostty config (their theme), and GhosttyKit
/// exposes no API to set colors. So instead we write our own theme file and, once
/// the host exists, build a config that loads the user's config *then* our theme
/// LAST (so our colors win) and apply it via `ghostty_app_update_config`
/// (see `RunwayTerminalHost`). The user's `~/.config/ghostty` is never modified.
enum RunwayTerminal {

    /// Body / terminal background (#0E1012) — must match `background` below so the
    /// inset around the terminal is seamless.
    static let body = Color(red: 0x0E / 255, green: 0x10 / 255, blue: 0x12 / 255)
    /// Header bar background (#191B1C) — a touch lighter than the body.
    static let headerBar = Color(red: 0x19 / 255, green: 0x1B / 255, blue: 0x1C / 255)

    /// Path to Runway's private Ghostty theme file.
    static let themeFilePath: String = {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        return (base ?? URL(fileURLWithPath: NSTemporaryDirectory()))
            .appendingPathComponent("Runway/runway-terminal-theme").path
    }()

    /// Writes the theme file. Idempotent; call once at launch before any terminal.
    static func installTheme() {
        let url = URL(fileURLWithPath: themeFilePath)
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? themeContents.write(to: url, atomically: true, encoding: .utf8)
    }

    private static let themeContents = """
    # Runway embedded-terminal theme: neutral near-black, opaque, flat.
    # Default ~2 zoom levels smaller than 11 so sessions fit comfortably.
    font-size = 9
    # Tame trackpad scroll in TUIs (claude, etc.); Ghostty's default (3) jumps.
    mouse-scroll-multiplier = 1
    background = 0e1012
    foreground = e6e6e6
    cursor-color = e6e6e6
    cursor-text = 0e1012
    selection-background = 2b2b33
    selection-foreground = ffffff
    background-opacity = 1
    window-padding-x = 2
    window-padding-y = 2
    window-padding-balance = true
    cursor-style = block
    palette = 0=#15151a
    palette = 1=#e5697b
    palette = 2=#6cc26c
    palette = 3=#e0a850
    palette = 4=#5aa6e0
    palette = 5=#b48ce0
    palette = 6=#5fc7c2
    palette = 7=#d6d6da
    palette = 8=#5a5a66
    palette = 9=#ef7a8b
    palette = 10=#7fd07f
    palette = 11=#edbf6a
    palette = 12=#74b6ef
    palette = 13=#c4a2ef
    palette = 14=#73d6d1
    palette = 15=#f2f2f5
    """
}
