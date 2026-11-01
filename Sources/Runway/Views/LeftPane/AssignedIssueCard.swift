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
        .background(
            TicketShape(stub: Self.stubWidth).fill(paper, style: FillStyle(eoFill: true))
        )
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

    private static let stubWidth: CGFloat = 96
    private static let notch: CGFloat = 3.5

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
    }

    private var paper: Color {
        isFlying ? Paper.flying : (hovering ? Paper.hover : Paper.base)
    }

    /// The split-flap board: one tile a digit, with the fold line across it.
    private var flaps: some View {
        HStack(spacing: 2) {
            ForEach(Array(String(issue.number).enumerated()), id: \.offset) { _, digit in
                Text(String(digit))
                    .font(.system(size: 14.5, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Paper.ink)
                    .frame(width: 16.5)
                    .padding(.vertical, 4)
                    .background(RoundedRectangle(cornerRadius: 3).fill(Paper.tile))
                    .overlay(Rectangle().fill(Color.black).frame(height: 1))
            }
        }
        .padding(.leading, 14)
        .padding(.vertical, 14)
    }

    private var destination: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(issue.title.uppercased())
                .font(.system(size: 14.5, weight: .medium, design: .monospaced))
                .tracking(0.6)
                .foregroundStyle(Paper.ink)
                .lineLimit(1)
                .truncationMode(.tail)

            HStack(spacing: 5) {
                Image(systemName: "airplane")
                    .font(.system(size: 9.5))
                    .foregroundStyle(Paper.muted)
                Text(repository.uppercased())
                    .font(.system(size: 10.5, design: .monospaced))
                    .tracking(1.2)
                    .foregroundStyle(Paper.muted)
                Text(verbatim: "·")
                    .font(.system(size: 10.5))
                    .foregroundStyle(Paper.faint)
                priorityBadge
                if let parent = issue.parent {
                    Text(verbatim: "·")
                        .font(.system(size: 10.5))
                        .foregroundStyle(Paper.faint)
                    Text("crew of \(GitHubNumber.reference(parent))")
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(Paper.faint)
                }
            }
            .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
    }

    /// The dashed tear line, running between the two notches bitten out of
    /// the card's own edge.
    private var perforation: some View {
        GeometryReader { geo in
            Path { path in
                let x = geo.size.width - Self.stubWidth
                path.move(to: CGPoint(x: x, y: Self.notch + 5))
                path.addLine(to: CGPoint(x: x, y: geo.size.height - Self.notch - 5))
            }
            .stroke(Paper.line.opacity(0.9), style: StrokeStyle(lineWidth: 1, dash: [2.5, 3]))
        }
        .allowsHitTesting(false)
    }

    // MARK: The stub

    private var status: FlightStatus { FlightStatus.of(issue) }

    private var stub: some View {
        let flown = FlightStatus.miles(of: issue)
        return VStack(spacing: 4) {
            Text(status.label)
                .font(.system(size: 10.5, design: .monospaced))
                .tracking(1.3)
                .foregroundStyle(stubColour)

            // One fixed slot, whatever it holds, so every card is the same
            // height whether it is flying or standing.
            VStack(spacing: 4) {
                switch status {
                case .scheduled:
                    Image(systemName: "airplane.departure")
                        .font(.system(size: 17))
                        .foregroundStyle(stubColour)
                case .landed:
                    Image(systemName: "airplane.arrival")
                        .font(.system(size: 17))
                        .foregroundStyle(stubColour)
                case .onAir:
                    Text("\(flown.done) \(flown.done == 1 ? "Mile" : "Miles")")
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundStyle(Paper.ink)
                    mileBar(flown).padding(.top, 2)
                }
            }
            .frame(height: 36)
        }
        .frame(width: Self.stubWidth)
        .padding(.vertical, 10)
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
        let width: CGFloat = 56
        return ZStack(alignment: .leading) {
            Capsule().fill(Paper.line).frame(width: width, height: 3)
            Capsule().fill(Paper.fill).frame(width: width * share, height: 3)
            // The plane sits at the tip of the fill and cuts its own gap in
            // the bar: the same shape twice, the lower one in the card's
            // colour and a size wider.
            ZStack {
                Image(systemName: "airplane")
                    .font(.system(size: 14, weight: .black))
                    .foregroundStyle(paper)
                Image(systemName: "airplane")
                    .font(.system(size: 9.5))
                    .foregroundStyle(Paper.plane)
            }
            .offset(x: width * share - 8)
        }
        .frame(width: width, alignment: .leading)
    }

    /// The gate class: "Class P1", only the tier in its own colour. Setting
    /// it is the right-click menu's job; this line is type, not a control,
    /// because the sheet draws it as part of the sentence under the title.
    private var priorityBadge: some View {
        let level = board.priority(issue.number, in: boardKey)
        return HStack(spacing: 4) {
            Text("Class")
                .font(.system(size: 10.5, design: .monospaced))
                .foregroundStyle(Paper.muted)
            Text(level.map(FlightPriority.label) ?? "P–")
                .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                .foregroundStyle(level.map { FlightPriority.color($0) } ?? Paper.faint)
        }
        .fixedSize()
    }

    private func copy(_ value: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }

}

/// A boarding pass: rounded, with two notches bitten out of it where the
/// stub tears off. Filled even-odd so the notches are holes, not circles.
struct TicketShape: Shape {
    let stub: CGFloat
    var notch: CGFloat = 3.5

    func path(in rect: CGRect) -> Path {
        var path = Path(roundedRect: rect, cornerRadius: 8)
        let x = rect.maxX - stub
        path.addEllipse(in: CGRect(
            x: x - notch, y: rect.minY - notch, width: notch * 2, height: notch * 2
        ))
        path.addEllipse(in: CGRect(
            x: x - notch, y: rect.maxY - notch, width: notch * 2, height: notch * 2
        ))
        return path
    }
}
