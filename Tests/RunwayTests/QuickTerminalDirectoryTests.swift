import Foundation
import Testing
@testable import Runway

@Suite("Quick terminal start directory")
struct QuickTerminalDirectoryTests {
    private let anyDirectory: (String) -> Bool = { _ in true }
    private let noDirectory: (String) -> Bool = { _ in false }

    @Test("Nothing configured means the shell picks its own directory")
    func emptyStaysEmpty() {
        #expect(QuickTerminalDirectory.resolved("", isDirectory: anyDirectory) == nil)
        #expect(QuickTerminalDirectory.resolved("   \n", isDirectory: anyDirectory) == nil)
    }

    @Test("A tilde path is expanded, trimmed, and stripped of trailing slashes")
    func expandsTilde() {
        let home = NSHomeDirectory()
        #expect(
            QuickTerminalDirectory.resolved("  ~/Developer/ ", isDirectory: anyDirectory)
                == "\(home)/Developer"
        )
        #expect(
            QuickTerminalDirectory.resolved("~", isDirectory: anyDirectory) == home
        )
    }

    @Test("An absolute path is kept as typed")
    func keepsAbsolutePath() {
        #expect(
            QuickTerminalDirectory.resolved("/Users/x/code//", isDirectory: anyDirectory)
                == "/Users/x/code"
        )
        #expect(QuickTerminalDirectory.resolved("/", isDirectory: anyDirectory) == "/")
    }

    @Test("Relative paths mean nothing to a shell Runway launches")
    func rejectsRelativePath() {
        #expect(QuickTerminalDirectory.resolved("Developer", isDirectory: anyDirectory) == nil)
        #expect(QuickTerminalDirectory.resolved("../up", isDirectory: anyDirectory) == nil)
    }

    @Test("A path that is not a folder falls back instead of failing the launch")
    func rejectsMissingFolder() {
        #expect(QuickTerminalDirectory.resolved("~/Developer", isDirectory: noDirectory) == nil)
    }

    @Test("A real folder resolves against the file system")
    func resolvesRealFolder() {
        #expect(QuickTerminalDirectory.resolved(NSHomeDirectory()) == NSHomeDirectory())
        #expect(QuickTerminalDirectory.directoryExists(NSHomeDirectory()))
        #expect(!QuickTerminalDirectory.directoryExists("/no/such/runway/folder"))
    }
}
