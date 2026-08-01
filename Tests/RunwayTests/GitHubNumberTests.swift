import Testing
@testable import Runway

@Suite("GitHub number formatting")
struct GitHubNumberTests {
    @Test("Issue and pull request references never use thousands separators")
    func plainDigits() {
        #expect(GitHubNumber.reference(10437) == "#10437")
        #expect(GitHubNumber.reference(1234567) == "#1234567")
    }
}
