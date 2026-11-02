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
    /// Lit while the pointer is on the class, so it reads as something you
    /// can click rather than a label.
    @State private var classHovering = false
    @State private var classMenu = PriorityMenu()
    private let board = FlightBoard.shared

    var body: some View {
        HStack(spacing: 0) {
            flaps
            destination
            stub
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            ZStack {
                RunwayCard.fill(hovering: hovering, selected: isFlying)
                // A little daylight behind the flaps and no further. The
                // tiles are the darkest thing on the card, so the paper
                // right behind them is where the contrast has to come
                // from; a wash that carried on under the title lit half
                // the card and stopped being a highlight.
                LinearGradient(
                    stops: [
                        .init(color: .white.opacity(0.05), location: 0),
                        .init(color: .white.opacity(0.034), location: 0.11),
                        .init(color: .clear, location: 0.26),
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            }
            .clipShape(ticket, style: FillStyle(eoFill: true))
            // And then the card's own bounds, which is the overflow-hidden
            // this needed all along. Even-odd counts a point that is inside
            // the notch circle but outside the card as *inside* the shape:
            // one crossing, not two. So each bite also painted a half disc
            // of card colour out into the gap, and the pair at a join met
            // as a full oval. Clipping to the rounded rect after the
            // even-odd clip throws that half away and leaves a bite.
            .clipShape(RoundedRectangle(cornerRadius: RunwayCard.radius))
        )
        // The hairline follows the bite round.
        //
        // Stroked at two points and clipped by the same shape: the half of
        // the line that falls outside the card is cut, and so is the half
        // inside each notch, which leaves one point of border everywhere
        // including round the curve. Stroking the plain rounded rect
        // instead drew a straight line across the mouth of each notch and
        // closed it back up, which is what made the pair at a card join
        // read as a bead on a string.
        .overlay(
            ticket
                .stroke(RunwayCard.border(hovering: hovering, selected: isFlying), lineWidth: 2)
                .clipShape(ticket, style: FillStyle(eoFill: true))
                .clipShape(RoundedRectangle(cornerRadius: RunwayCard.radius))
        )
        .overlay(alignment: .leading) { perforation }
        .contentShape(Rectangle())
        // No lift on hover. The paper already goes a shade lighter, and a
        // card that also jumps a point makes a list twitch as the pointer
        // runs down it.
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
        static let tile = Color(red: 0.055, green: 0.059, blue: 0.063)   // #0e0f10
        static let line = Color(red: 0.18, green: 0.188, blue: 0.2)      // #2e3033
        static let fill = Color(red: 0.275, green: 0.282, blue: 0.298)   // #46484c
        static let plane = Color(red: 0.463, green: 0.471, blue: 0.486)  // #76787c
        static let ink = Color(red: 0.945, green: 0.945, blue: 0.933)    // #f1f1ee
        static let muted = Color(red: 0.541, green: 0.549, blue: 0.565)  // #8a8c90
        static let faint = Color(red: 0.333, green: 0.341, blue: 0.357)  // #55575b
    }

    /// What the plane cuts its gap out of: the card's own fill, so the notch
    /// in the transit bar is invisible rather than a grey smudge.
    private var paper: Color {
        RunwayCard.fill(hovering: hovering, selected: isFlying)
    }

    /// The split-flap board: one tile a digit, shaded behind the glyph so
    /// the digit itself stays clean. `FlapTile` holds the look, shared with
    /// the pane's header.
    private var flaps: some View {
        FlapNumber(number: issue.number, size: 11.5)
            .padding(.leading, 11)
            .padding(.vertical, 11)
    }

    private var destination: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(issue.title.uppercased())
                .font(.mono(11.5, .medium))
                .tracking(0.5)
                .foregroundStyle(Paper.ink)
                .lineLimit(1)
                .truncationMode(.tail)

            HStack(spacing: 4) {
                Image(systemName: "airplane")
                    .font(.system(size: 8))
                    .foregroundStyle(Paper.muted)
                Text(repository.uppercased())
                    .font(.mono(8.5))
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
                        .font(.mono(8.5))
                        .foregroundStyle(Paper.faint)
                }
            }
            .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 11)
    }

    /// The card with its two bites taken out: the stub tears off along the
    /// perforation, so the card is notched where the line meets each edge.
    private var ticket: TicketShape {
        TicketShape(
            stub: Self.stubWidth,
            notch: Self.notch,
            corner: RunwayCard.radius
        )
    }

    private static let notch: CGFloat = 4

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
                let clear = Self.notch + 4
                path.move(to: CGPoint(x: x, y: clear))
                path.addLine(to: CGPoint(x: x, y: geo.size.height - clear))
            }
            .stroke(Paper.line.opacity(0.9), style: StrokeStyle(lineWidth: 1, dash: [2.5, 3]))
        }
        .allowsHitTesting(false)
    }

    // MARK: The stub

    private var status: FlightStatus { FlightStatus.of(issue) }

    private var stub: some View {
        let flown = FlightStatus.transits(of: issue)
        return VStack(spacing: 5) {
            Text(status.label)
                .font(.mono(8.5))
                .tracking(1.1)
                .foregroundStyle(stubColour)

            // One slot, one line each, whatever the flight is doing: a
            // word, then either a plane or a bar. A stacked count pushed
            // the bar down on a flying card only, so three cards in a row
            // had their marks at three different heights.
            ZStack {
                switch status {
                case .scheduled:
                    Image(systemName: "airplane.departure")
                        .font(.system(size: 13))
                        .foregroundStyle(stubColour)
                case .landed:
                    Image(systemName: "airplane.arrival")
                        .font(.system(size: 13))
                        .foregroundStyle(stubColour)
                case .onAir:
                    transitBar(flown)
                }
            }
            .frame(height: 14)
        }
        .frame(width: Self.stubWidth)
        .padding(.vertical, 9)
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
    private func transitBar(_ flown: (done: Int, total: Int)) -> some View {
        let share = flown.total > 0 ? Double(flown.done) / Double(flown.total) : 0
        let width: CGFloat = 46
        return ZStack(alignment: .leading) {
            Capsule().fill(Paper.line).frame(width: width, height: 2.5)
            // The fill stops just short of the plane rather than under it.
            // A capsule's rounded tip reached past the black outline on a
            // long bar and showed as a pixel of grey in the gap the plane
            // is supposed to have cut.
            Capsule()
                .fill(Paper.fill)
                .frame(width: max(0, width * share - 3), height: 2.5)
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
                .font(.mono(8.5))
                .foregroundStyle(classHovering ? Paper.ink : Paper.muted)
            Text(level.map(FlightPriority.label) ?? "P-")
                .font(.mono(8.5, .semibold))
                .foregroundStyle(level.map { FlightPriority.color($0) } ?? Paper.faint)
        }
        .fixedSize()
        // A click on the class opens the list, which is the one thing you
        // ever want to do to it. Not a SwiftUI Menu: that draws its own
        // control chrome on the card, and the headless render of the board
        // came out with a yellow prohibitory badge where the class should
        // be. An NSMenu at the pointer is plain text until you click it.
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .onHover { classHovering = $0 }
        .pointerCursor()
        .help("Set this flight's class")
        .onTapGesture {
            classMenu.show(current: level) { chosen in
                board.setPriority(chosen, for: issue.number, in: boardKey)
            }
        }
    }

    private func copy(_ value: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }

}


/// A ticket: a rounded card with a round bite out of each long edge, where
/// the perforation meets it.
///
/// The bites are holes, not drawn shapes. The path is the card plus two
/// whole circles centred on the top and bottom edges, filled even-odd, so
/// the circles punch through rather than paint. Filling it any other way
/// would stack a second colour over the card and the "hole" would be a
/// grey disc.
struct TicketShape: Shape {
    /// Width of the stub, measured from the right edge: the perforation
    /// sits at its left side.
    var stub: CGFloat
    var notch: CGFloat
    var corner: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path(roundedRect: rect, cornerRadius: corner)
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


/// The class list, as a plain AppKit menu at the pointer.
///
/// SwiftUI's `Menu` would do this in one line, but it brings a control's
/// chrome with it and the class has to read as part of the sentence under
/// the title. This keeps the label as type and only shows a menu on the
/// click.
@MainActor
final class PriorityMenu: NSObject {
    private var pick: ((Int?) -> Void)?

    /// `current` is ticked, and "None" clears it.
    func show(current: Int?, pick: @escaping (Int?) -> Void) {
        self.pick = pick
        let menu = NSMenu()
        for level in FlightPriority.all {
            let item = NSMenuItem(
                title: FlightPriority.label(level),
                action: #selector(choose(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.tag = level
            item.state = current == level ? .on : .off
            menu.addItem(item)
        }
        menu.addItem(.separator())
        let none = NSMenuItem(title: "None", action: #selector(choose(_:)), keyEquivalent: "")
        none.target = self
        none.tag = 0
        none.state = current == nil ? .on : .off
        menu.addItem(none)
        // No view, so the point is in screen coordinates, which is where
        // the mouse already is.
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }

    @objc private func choose(_ sender: NSMenuItem) {
        pick?(sender.tag == 0 ? nil : sender.tag)
    }
}
