import Foundation
import Testing
@testable import Runway

@Suite("The issue a branch belongs to")
struct BranchIssueTests {
    @Test("A branch names its issue last, by convention")
    func trailingNumber() {
        #expect(BranchIssue.number(in: "feat/designer-images-page-16283") == 16283)
        #expect(BranchIssue.number(in: "fix/sales-hour-axis-16252") == 16252)
    }

    @Test("A branch without a trailing number has no issue")
    func noNumber() {
        #expect(BranchIssue.number(in: "main") == nil)
        #expect(BranchIssue.number(in: "release/kiosk-v1.6") == nil)
        #expect(BranchIssue.number(in: "-16283") == nil)
    }

    @Test("The number is the whole last word, never a digit inside one")
    func wholeWordOnly() {
        #expect(BranchIssue.number(in: "port/kiosk-v1.6-batch2") == nil)
        #expect(BranchIssue.split("feat/pos-booking-16257").number == "-16257")
    }
}
