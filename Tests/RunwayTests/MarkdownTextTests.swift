import Foundation
import Testing

@testable import Runway

@Suite("Issue text reads as Markdown")
struct MarkdownTextTests {
    @Test("A link shows its label, not its URL")
    func linkShowsLabel() {
        let line = "[#17340](https://github.com/VISKA-IO/monorepo/pull/17340) reviewed and merged."
        let rendered = String(MarkdownText.attributed(line).characters)
        #expect(rendered == "#17340 reviewed and merged.")
    }

    @Test("Two links in one sentence both resolve")
    func twoLinks() {
        let line = "[#17338](https://x/1) merged, with [#17337](https://x/2) on main first."
        let rendered = String(MarkdownText.attributed(line).characters)
        #expect(rendered == "#17338 merged, with #17337 on main first.")
    }

    @Test("A line that is not Markdown comes back as itself")
    func plainLine() {
        let line = "The Vercel sites run on React Router 8."
        #expect(String(MarkdownText.attributed(line).characters) == line)
    }

    @Test("A stray bracket loses nothing")
    func strayBracket() {
        let line = "Check [this one and move on"
        #expect(String(MarkdownText.attributed(line).characters) == line)
    }
}
