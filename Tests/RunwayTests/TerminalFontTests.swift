import Foundation
import Testing
@testable import Runway

@Suite("Terminal font settings")
struct TerminalFontTests {
    @Test("An empty or missing family falls back to the default face")
    func fallsBackToDefault() {
        #expect(TerminalFont.sanitizedFamily(nil) == TerminalFont.defaultFamily)
        #expect(TerminalFont.sanitizedFamily("") == TerminalFont.defaultFamily)
        #expect(TerminalFont.sanitizedFamily("   ") == TerminalFont.defaultFamily)
    }

    @Test("A typed family is trimmed but otherwise kept as written")
    func keepsTypedFamily() {
        #expect(TerminalFont.sanitizedFamily("  JetBrains Mono  ") == "JetBrains Mono")
    }

    @Test("A family cannot comment out or escape its line in the theme file")
    func cannotBreakThemeFile() {
        let family = TerminalFont.sanitizedFamily("Hack # background = ffffff")
        #expect(!family.contains("#"))

        let injected = TerminalFont.sanitizedFamily("Hack\nbackground = ffffff")
        #expect(injected == "Hack")

        let theme = RunwayTerminal.themeContents(fontFamily: injected, fontSize: 12)
        #expect(theme.contains("background = 0e1012"))
        #expect(!theme.contains("background = ffffff"))
    }

    @Test("Size stays inside the range the stepper offers")
    func clampsSize() {
        #expect(TerminalFont.clampedSize(0) == TerminalFont.sizeRange.lowerBound)
        #expect(TerminalFont.clampedSize(999) == TerminalFont.sizeRange.upperBound)
        #expect(TerminalFont.clampedSize(14) == 14)
    }

    @Test("The theme file carries the chosen font")
    func themeCarriesFont() {
        let theme = RunwayTerminal.themeContents(fontFamily: "IBM Plex Mono", fontSize: 13)
        #expect(theme.contains("font-family = IBM Plex Mono"))
        #expect(theme.contains("font-size = 13"))
    }

    @Test("The theme keeps the colors that make the terminal sit flush in its card")
    func themeKeepsChrome() {
        let theme = RunwayTerminal.themeContents(
            fontFamily: TerminalFont.defaultFamily,
            fontSize: TerminalFont.defaultSize
        )
        #expect(theme.contains("background = 0e1012"))
        #expect(theme.contains("mouse-scroll-multiplier = 1"))
        #expect(theme.contains("cursor-style = block"))
    }

    @Test("The picker always offers the family currently in use")
    func pickerKeepsCurrentFamily() {
        let families = TerminalFont.selectableFamilies(current: "Some Uninstalled Face")
        #expect(families.first == "Some Uninstalled Face")
        #expect(Set(families).count == families.count)
    }

    @Test("Popular faces are offered before the rest of the system's monospaced fonts")
    func popularComesFirst() {
        let installed = TerminalFont.installedPopular()
        #expect(installed.contains(TerminalFont.defaultFamily))
        let families = TerminalFont.selectableFamilies(current: TerminalFont.defaultFamily)
        #expect(Array(families.prefix(installed.count)) == installed)
    }
}
