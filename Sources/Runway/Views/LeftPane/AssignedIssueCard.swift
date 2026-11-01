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
        .background(Self.ticket(stub: Self.stubWidth).fill(paper, style: FillStyle(eoFill: true)))
        .overlay(
            Self.ticket(stub: Self.stubWidth)
                .stroke(Color.white.opacity(isFlying ? 0.18 : (hovering ? 0.12 : 0.06)), lineWidth: 1)
        )
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

    /// The boarding-pass outline: a rounded card with the stub's perforation
    /// punched through it as two notches, the way a torn ticket reads.
    private static func ticket(stub: CGFloat) -> some Shape { TicketShape(stub: stub) }

    private static let stubWidth: CGFloat = 92
    private static let notch: CGFloat = 5

    private var paper: Color {
        isFlying
            ? Color(red: 0.16, green: 0.17, blue: 0.18)
            : (hovering ? Color(red: 0.125, green: 0.13, blue: 0.14)
                        : Color(red: 0.094, green: 0.098, blue: 0.106))
    }

    /// The split-flap board: one tile a digit, with the fold line across it.
    private var flaps: some View {
        HStack(spacing: 2) {
            ForEach(Array(String(issue.number).enumerated()), id: \.offset) { _, digit in
                Text(String(digit))
                    .font(.system(size: 12.5, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.88))
                    .frame(width: 13)
                    .padding(.vertical, 4)
                    .background(RoundedRectangle(cornerRadius: 3).fill(Color(white: 0.055)))
                    .overlay(Rectangle().fill(Color.black).frame(height: 1))
            }
        }
        .padding(.leading, 12)
        .padding(.vertical, 13)
    }

    private var destination: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(issue.title.uppercased())
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .tracking(0.4)
                .foregroundStyle(Color.white.opacity(0.94))
                .lineLimit(1)
                .truncationMode(.tail)

            HStack(spacing: 5) {
                Image(systemName: "airplane")
                    .font(.system(size: 8))
                    .foregroundStyle(Color.white.opacity(0.34))
                Text(repository.uppercased())
                    .font(.system(size: 8.5, design: .monospaced))
                    .tracking(0.5)
                    .foregroundStyle(Color.white.opacity(0.42))
                Text(verbatim: "·")
                    .font(.system(size: 8.5))
                    .foregroundStyle(Color.white.opacity(0.22))
                priorityBadge
                if let parent = issue.parent {
                    Text(verbatim: "·")
                        .font(.system(size: 8.5))
                        .foregroundStyle(Color.white.opacity(0.22))
                    Text("CREW OF \(GitHubNumber.reference(parent))")
                        .font(.system(size: 8.5, design: .monospaced))
                        .foregroundStyle(Color.white.opacity(0.3))
                }
            }
            .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
    }

    /// The dashed tear line, with the notches already cut out of the card
    /// behind it.
    private var perforation: some View {
        GeometryReader { geo in
            Path { path in
                let x = geo.size.width - Self.stubWidth
                path.move(to: CGPoint(x: x, y: Self.notch + 4))
                path.addLine(to: CGPoint(x: x, y: geo.size.height - Self.notch - 4))
            }
            .stroke(
                Color.white.opacity(0.1),
                style: StrokeStyle(lineWidth: 1, dash: [3, 3])
            )
        }
        .allowsHitTesting(false)
    }

    // MARK: The stub

    private var status: FlightStatus { FlightStatus.of(issue) }

    private var stub: some View {
        let flown = FlightStatus.miles(of: issue)
        return VStack(spacing: 4) {
            Text(status.label)
                .font(.system(size: 8, weight: .semibold, design: .monospaced))
                .tracking(1.1)
                .foregroundStyle(status.color)

            // One fixed slot, whatever it holds, so every card is the same
            // height whether it is flying or standing.
            VStack(spacing: 4) {
                switch status {
                case .scheduled:
                    Image(systemName: "airplane.departure")
                        .font(.system(size: 13))
                        .foregroundStyle(status.color.opacity(0.7))
                case .landed:
                    Image(systemName: "airplane.arrival")
                        .font(.system(size: 13))
                        .foregroundStyle(status.color.opacity(0.8))
                case .onAir:
                    Text("\(flown.done) \(flown.done == 1 ? "Mile" : "Miles")")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(Color.white.opacity(0.82))
                    mileBar(flown)
                }
            }
            .frame(height: 30)
        }
        .frame(width: Self.stubWidth)
        .padding(.vertical, 10)
    }

    /// How far down the runway it is. The bar is grey on purpose: the status
    /// word above it already carries the colour, and two of them read as two
    /// different facts.
    private func mileBar(_ flown: (done: Int, total: Int)) -> some View {
        let share = flown.total > 0 ? Double(flown.done) / Double(flown.total) : 0
        let width: CGFloat = 54
        return ZStack(alignment: .leading) {
            Capsule().fill(Color(white: 0.18)).frame(width: width, height: 3)
            Capsule().fill(Color(white: 0.28)).frame(width: width * share, height: 3)
            // The plane sits at the tip of the fill and cuts its own gap in
            // the bar: the same shape twice, the lower one in the card's
            // colour and a size wider.
            ZStack {
                Image(systemName: "airplane")
                    .font(.system(size: 11, weight: .black))
                    .foregroundStyle(paper)
                Image(systemName: "airplane")
                    .font(.system(size: 8))
                    .foregroundStyle(Color(white: 0.46))
            }
            .rotationEffect(.degrees(0))
            .offset(x: width * share - 7)
        }
        .frame(width: width, alignment: .leading)
    }

    /// The gate class: "Class P1", only the tier in its own colour, and the
    /// whole thing is the menu that sets it.
    private var priorityBadge: some View {
        let level = board.priority(issue.number, in: boardKey)
        return Menu {
            ForEach(FlightPriority.all, id: \.self) { choice in
                Button(FlightPriority.label(choice)) {
                    board.setPriority(choice, for: issue.number, in: boardKey)
                }
            }
            Divider()
            Button("None") { board.setPriority(nil, for: issue.number, in: boardKey) }
        } label: {
            HStack(spacing: 3) {
                Text("CLASS")
                    .font(.system(size: 8.5, design: .monospaced))
                    .tracking(0.5)
                    .foregroundStyle(Color.white.opacity(0.42))
                Text(level.map(FlightPriority.label) ?? "P–")
                    .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                    .foregroundStyle(
                        level.map { FlightPriority.color($0) } ?? Color.white.opacity(0.3)
                    )
            }
            .fixedSize()
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .pointerCursor()
        .help("Set this flight's priority")
        .opacity(level == nil && !hovering ? 0.45 : 1)
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
    var notch: CGFloat = 5

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
