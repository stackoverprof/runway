import Foundation
import Testing
@testable import Runway

@Suite("Reading an issue body")
struct IssueBodyTests {
    private let body = """
    ## Idea
    Bookings should be takeable on the POS.

    ## Acceptance
    - A booking taken on the POS appears in the dashboard within a minute.
    - A cancelled booking refunds in full, once.

    ## Progress
    _Updated 30 Oct 14:02 WIB_
    - [x] Booking form on the POS
    - [X] Hold a slot while paying
    - [ ] Refund a cancelled booking
    - [ ] /close

    ## Situation Development
    **Channel:** #engineering

    **Thu, 30 Oct**
    - [Erbin](https://viska.slack.com/archives/C1/p1): Brauð wants bookings before 2 Jan.
    - [Arnar](https://viska.slack.com/archives/C1/p2): refunds go through the same Teya path.

    ## References
    Nothing yet.
    """

    @Test("A section stops at the next heading")
    func sectionBounds() {
        let acceptance = IssueBody.section("Acceptance", in: body)
        #expect(acceptance.contains { $0.contains("appears in the dashboard") })
        #expect(!acceptance.contains { $0.contains("Hold a slot") })
    }

    @Test("Steps read ticked and unticked alike, bullets included")
    func steps() {
        let steps = IssueBody.steps("Progress", in: body)
        #expect(steps.count == 4)
        #expect(steps[0] == IssueBody.Step(text: "Booking form on the POS", done: true))
        #expect(steps[1].done)
        #expect(!steps[2].done)

        let acceptance = IssueBody.steps("Acceptance", in: body)
        #expect(acceptance.count == 2)
        #expect(!acceptance[0].done)
    }

    @Test("A heading carrying more than its name still matches")
    func headingWithSuffix() {
        let withStamp = "## Progress (ordered)\n- [ ] one\n"
        #expect(IssueBody.steps("Progress", in: withStamp).count == 1)
    }

    @Test("The conversation keeps who said it and where")
    func conversation() {
        let entries = IssueBody.conversation("Situation Development", in: body)
        #expect(entries.count == 2)
        #expect(entries[0].who == "Erbin")
        #expect(entries[0].said == "Brauð wants bookings before 2 Jan.")
        #expect(entries[0].link?.host == "viska.slack.com")
        #expect(IssueBody.homeThread("Situation Development", in: body) == entries[0].link)
    }

    @Test("A body with none of these sections gives nothing, and does not crash")
    func emptyBody() {
        #expect(IssueBody.steps("Acceptance", in: "Just a sentence.").isEmpty)
        #expect(IssueBody.conversation("Situation Development", in: "").isEmpty)
        #expect(IssueBody.homeThread("Situation Development", in: "## Situation Development\n") == nil)
    }
}
