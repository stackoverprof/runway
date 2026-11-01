import AppKit
import SwiftUI

/// One issue in the Runway tab.
struct AssignedIssueCard: View {
    let issue: AssignedIssue
    /// What the card prints: the clone's own name, `monorepo`.
    let repository: String
    /// What the board is keyed by: `owner/name`. The two are different
    /// strings, and using the short one here is why a priority set from an
    /// agent never showed on the card.
    var boardKey: String = ""
    /// True when this is the issue the other two panes are answering for.
    var isFlying = false
    /// Open or close the issue from the card. Absent means no state menu.
    var onSetClosed: ((Bool) -> Void)?
    @State private var hovering = false
    private let board = FlightBoard.shared

    var body: some View {
        HStack(spacing: 0) {
            flaps
            destination
            stub
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(paper))
        // No border at all, the way the sheet draws it. A hairline looks
        // harmless until it runs through the notches: it closes the bite
        // back up and the pair at a card join reads as a bead on a string.
        // The flight on screen is told apart by its lighter paper instead.
        .overlay(alignment: .leading) { perforation }
        .contentShape(Rectangle())
        .offset(y: hovering ? -1 : 0)
        .animation(.easeOut(duration: 0.15), value: hovering)
        .onHover { hovering = $0 }
        .contextMenu {
            Button("Copy issue name") { copy("\(issue.title) \(GitHubNumber.reference(issue.number))") }
            Button("Copy issue number") { copy(GitHubNumber.reference(issue.number)) }
            Button("Copy issue link") { copy(issue.url.absoluteString) }
            Button("Open link") { NSWorkspace.shared.open(issue.url) }
            if let onSetClosed {
                Divider()
                Button(issue.isClosed ? "Reopen issue" : "Close issue") {
                    onSetClosed(!issue.isClosed)
                }
            }
            Divider()
            Menu("Priority") {
                ForEach(FlightPriority.all, id: \.self) { level in
                    Button(FlightPriority.label(level)) {
                        board.setPriority(level, for: issue.number, in: boardKey)
                    }
                }
                Divider()
                Button("None") { board.setPriority(nil, for: issue.number, in: boardKey) }
            }
        }
    }

    // MARK: The ticket

    private static let stubWidth: CGFloat = 80

    /// The sheet's own palette. Named here so the card reads as the design
    /// and not as a pile of literals.
    private enum Paper {
        static let base = Color(red: 0.094, green: 0.098, blue: 0.106)   // #18191b
        static let hover = Color(red: 0.125, green: 0.129, blue: 0.141)  // #202124
        static let flying = Color(red: 0.16, green: 0.165, blue: 0.18)
        static let tile = Color(red: 0.055, green: 0.059, blue: 0.063)   // #0e0f10
        static let line = Color(red: 0.18, green: 0.188, blue: 0.2)      // #2e3033
        static let fill = Color(red: 0.275, green: 0.282, blue: 0.298)   // #46484c
        static let plane = Color(red: 0.463, green: 0.471, blue: 0.486)  // #76787c
        static let ink = Color(red: 0.945, green: 0.945, blue: 0.933)    // #f1f1ee
        static let muted = Color(red: 0.541, green: 0.549, blue: 0.565)  // #8a8c90
        static let faint = Color(red: 0.333, green: 0.341, blue: 0.357)  // #55575b
        /// The miles count, pitched to the bar it sits on rather than the title.
        static let mile = Color(red: 0.416, green: 0.424, blue: 0.439)   // #6a6c70
    }

    private var paper: Color {
        isFlying ? Paper.flying : (hovering ? Paper.hover : Paper.base)
    }

    /// The split-flap board: one tile a digit.
    ///
    /// The seam is not a drawn line. Each tile's own face darkens into the
    /// middle and back out, and a second gradient lies over the digit as
    /// well, so the number reads as curving into the fold the way an open
    /// book's gutter does. A 1-point black rule did the same job at a
    /// distance and looked like a scratch up close.
    private var flaps: some View {
        HStack(spacing: 2) {
            ForEach(Array(String(issue.number).enumerated()), id: \.offset) { _, digit in
                Text(String(digit))
                    .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Paper.ink)
                    .frame(width: 13)
                    .padding(.vertical, 3)
                    .background(Self.flapFace)
                    .overlay(Self.flapFold)
                    .clipShape(RoundedRectangle(cornerRadius: 2.5))
            }
        }
        .padding(.leading, 11)
        .padding(.vertical, 11)
    }

    /// The tile's own face: light at the edges, nearly black at the seam.
    private static let flapFace = LinearGradient(
        stops: [
            .init(color: Color(red: 0.114, green: 0.118, blue: 0.129), location: 0),    // #1d1e21
            .init(color: Color(red: 0.071, green: 0.075, blue: 0.082), location: 0.46), // #121315
            .init(color: Color(red: 0.031, green: 0.035, blue: 0.039), location: 0.50), // #08090a
            .init(color: Color(red: 0.071, green: 0.075, blue: 0.082), location: 0.54),
            .init(color: Color(red: 0.114, green: 0.118, blue: 0.129), location: 1),
        ],
        startPoint: .top, endPoint: .bottom
    )

    /// The same shadow again, this time over the digit.
    private static let flapFold = LinearGradient(
        stops: [
            .init(color: .clear, location: 0.28),
            .init(color: .black.opacity(0.5), location: 0.47),
            .init(color: .black.opacity(0.7), location: 0.50),
            .init(color: .black.opacity(0.5), location: 0.53),
            .init(color: .clear, location: 0.72),
        ],
        startPoint: .top, endPoint: .bottom
    )

    private var destination: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(issue.title.uppercased())
                .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                .tracking(0.5)
                .foregroundStyle(Paper.ink)
                .lineLimit(1)
                .truncationMode(.tail)

            HStack(spacing: 4) {
                Image(systemName: "airplane")
                    .font(.system(size: 8))
                    .foregroundStyle(Paper.muted)
                Text(repository.uppercased())
                    .font(.system(size: 8.5, design: .monospaced))
                    .tracking(1)
                    .foregroundStyle(Paper.muted)
                Text(verbatim: "·")
                    .font(.system(size: 8.5))
                    .foregroundStyle(Paper.faint)
                priorityBadge
                if let parent = issue.parent {
                    Text(verbatim: "·")
                        .font(.system(size: 8.5))
                        .foregroundStyle(Paper.faint)
                    Text("crew of \(GitHubNumber.reference(parent))")
                        .font(.system(size: 8.5, design: .monospaced))
                        .foregroundStyle(Paper.faint)
                }
            }
            .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 11)
    }

    /// The dashed tear line.
    ///
    /// No bite at its ends, whatever the sheet draws. A notch is a half
    /// circle on the card's edge, the cards sit 10 points apart, and at this
    /// size one card's notch and the next one's close into a dark blob
    /// across the gap: checked at 3x zoom on the running app, at radius 5,
    /// at 3.5, and as a 2-point scallop. The dashes alone say the stub tears
    /// off, and nothing is left to read as a bead.
    private var perforation: some View {
        GeometryReader { geo in
            Path { path in
                let x = geo.size.width - Self.stubWidth
                path.move(to: CGPoint(x: x, y: 6))
                path.addLine(to: CGPoint(x: x, y: geo.size.height - 6))
            }
            .stroke(Paper.line.opacity(0.9), style: StrokeStyle(lineWidth: 1, dash: [2.5, 3]))
        }
        .allowsHitTesting(false)
    }

    // MARK: The stub

    private var status: FlightStatus { FlightStatus.of(issue) }

    private var stub: some View {
        let flown = FlightStatus.miles(of: issue)
        return VStack(spacing: 3) {
            Text(status.label)
                .font(.system(size: 8.5, design: .monospaced))
                .tracking(1.1)
                .foregroundStyle(stubColour)

            // One fixed slot, whatever it holds, so every card is the same
            // height whether it is flying or standing.
            VStack(spacing: 0) {
                switch status {
                case .scheduled:
                    Image(systemName: "airplane.departure")
                        .font(.system(size: 11))
                        .foregroundStyle(stubColour)
                case .landed:
                    Image(systemName: "airplane.arrival")
                        .font(.system(size: 11))
                        .foregroundStyle(stubColour)
                case .onAir:
                    Text("\(flown.done) \(flown.done == 1 ? "Mile" : "Miles")")
                        .font(.system(size: 8.5, design: .monospaced))
                        .tracking(0.4)
                        .foregroundStyle(Paper.mile)
                    mileBar(flown).padding(.top, 2)
                }
            }
            .frame(height: 24)
        }
        .frame(width: Self.stubWidth)
        .padding(.vertical, 7)
    }

    /// The sheet's own three: grey while it waits, teal in the air, purple
    /// once it is down.
    private var stubColour: Color {
        switch status {
        case .scheduled: Paper.muted
        case .onAir: Color(red: 0.486, green: 0.776, blue: 0.722)   // #7cc6b8
        case .landed: Color(red: 0.663, green: 0.545, blue: 0.941)  // #a98bf0
        }
    }

    /// How far down the runway it is. The bar is grey on purpose: the status
    /// word above it already carries the colour, and two of them read as two
    /// different facts.
    private func mileBar(_ flown: (done: Int, total: Int)) -> some View {
        let share = flown.total > 0 ? Double(flown.done) / Double(flown.total) : 0
        let width: CGFloat = 46
        return ZStack(alignment: .leading) {
            Capsule().fill(Paper.line).frame(width: width, height: 2.5)
            Capsule().fill(Paper.fill).frame(width: width * share, height: 2.5)
            // The plane sits at the tip of the fill and cuts its own gap in
            // the bar: the same shape twice, the lower one in the card's
            // colour and a size wider.
            ZStack {
                Image(systemName: "airplane")
                    .font(.system(size: 11.5, weight: .black))
                    .foregroundStyle(paper)
                Image(systemName: "airplane")
                    .font(.system(size: 8))
                    .foregroundStyle(Paper.plane)
            }
            .offset(x: width * share - 6.5)
        }
        .frame(width: width, alignment: .leading)
    }

    /// The gate class: "Class P1", only the tier in its own colour. Setting
    /// it is the right-click menu's job; this line is type, not a control,
    /// because the sheet draws it as part of the sentence under the title.
    private var priorityBadge: some View {
        let level = board.priority(issue.number, in: boardKey)
        return HStack(spacing: 3) {
            Text("Class")
                .font(.system(size: 8.5, design: .monospaced))
                .foregroundStyle(Paper.muted)
            Text(level.map(FlightPriority.label) ?? "P-")
                .font(.system(size: 8.5, weight: .semibold, design: .monospaced))
                .foregroundStyle(level.map { FlightPriority.color($0) } ?? Paper.faint)
        }
        .fixedSize()
    }

    private func copy(_ value: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }

}
