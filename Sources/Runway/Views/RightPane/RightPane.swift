import AppKit
import SwiftUI

/// The crew pane: one box per leg of the flight.
///
/// A crew is either active or stood down. Stood down it is a card, the same
/// card the issue reads as elsewhere, costing nothing but a line. Activated it
/// opens into its terminal, and the active crews share the pane between them,
/// the one you are reading taking the larger share. The pane never scrolls:
/// every crew of the flight is on screen at once.
///
/// Placeholder content: no crew model exists yet, so this is the shape.
struct RightPane: View {
    @Bindable var ws: Workspace
    @Bindable var issues: AssignedIssues
    /// Which crews are up is shared with the agents, so a pilot can stand one
    /// up as well as you can. Which one you are reading is yours alone.
    private let deck = CrewDeck.shared
    @State private var reading: Int?
    /// What was copied a moment ago, so the label can flash.
    @State private var copied: String?
    /// The landed crew under the pointer, whose tick becomes a play.
    @State private var hoveringLanded: Int?
    /// The pane's own view, so a click anywhere else in the window can be
    /// told apart from a click on a crew.
    @State private var paneView = PaneViewBox()
    @State private var clickWatch: Any?

    /// Every crew of the flight, landed ones included. A crew that closes
    /// has not stopped being part of the flight, and a pane that forgets it
    /// loses the shape of what was done.
    ///
    /// The order is the flight's own, the order its crews were put under it,
    /// which the pilot sets with `runway crew order`. Landed crews collect at
    /// the bottom: they are one line each and nothing is waiting on them, so
    /// leaving one between two live crews only breaks the reading.
    private var crews: [IssueLeg] {
        let legs = issues.issue(ws.flightNumber)?.legs ?? []
        return legs.filter { !$0.isClosed } + legs.filter(\.isClosed)
    }

    /// Where a crew's issue lives, which is how the deck names its seat.
    private func crewRepositoryName(_ crew: IssueLeg) -> String {
        crew.repository ?? issues.repository ?? ""
    }

    private func isUp(_ crew: IssueLeg) -> Bool {
        deck.isUp(crewRepositoryName(crew), crew.number)
    }

    var body: some View {
        // The cards take their own height, measured rather than guessed, and
        // the crews that are up divide every point that is left.
        CrewAccordion(spacing: CrewAccordion.gap, minimumBox: CrewAccordion.minimumBox) {
            ForEach(crews) { crew in
                if crew.isClosed, !isUp(crew) {
                    landedCard(crew)
                        .layoutValue(key: CrewShareKey.self, value: 0)
                } else if isUp(crew) {
                    activeBox(crew)
                        .layoutValue(
                            key: CrewShareKey.self,
                            value: reading == crew.number ? 2 : 1
                        )
                } else {
                    standingCard(crew)
                        .layoutValue(key: CrewShareKey.self, value: 0)
                }
            }
        }
        .padding(.horizontal, 7)
        .padding(.bottom, 7)
        .padding(.top, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .clipped()
        .contentShape(Rectangle())
        .background(PaneHitArea(box: paneView))
        // Reading one crew larger is a choice that lasts only while you are
        // in the pane. Click the pilot, the left pane, anything else, and the
        // crews go back to an equal share.
        .onAppear { watchClicks() }
        .onDisappear {
            if let clickWatch { NSEvent.removeMonitor(clickWatch) }
            clickWatch = nil
        }
        .overlay {
            if crews.isEmpty { noCrews }
        }
        .background(Color.black)
    }

    /// Any click in the window that did not land on this pane clears the
    /// choice. A click inside it is left alone: the crew boxes decide.
    private func watchClicks() {
        guard clickWatch == nil else { return }
        clickWatch = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { event in
            Task { @MainActor in
                guard reading != nil, let view = paneView.view else { return }
                let inside = view.window === event.window
                    && view.bounds.contains(view.convert(event.locationInWindow, from: nil))
                if !inside {
                    withAnimation(.easeInOut(duration: 0.22)) { reading = nil }
                }
            }
            return event
        }
    }

    private var noCrews: some View {
        VStack(spacing: 7) {
            Image(systemName: "person.2")
                .font(.system(size: 16))
                .foregroundStyle(Color.white.opacity(0.14))
            Text(ws.flightNumber == nil ? "No flight picked" : "This flight has no crews yet")
                .font(.system(size: 12))
                .foregroundStyle(Color.white.opacity(0.28))
        }
    }

    /// A crew that landed: one line, no control, out of the way.
    private func landedCard(_ crew: IssueLeg) -> some View {
        HStack(spacing: 8) {
            // Purple is closed everywhere else in Runway: the left pane's
            // card, the Close button, a merged PR. A landed crew matches.
            // Hovering turns the tick into a play, because a closed issue
            // still has a session worth asking something.
            Button {
                bringUp(crew)
            } label: {
                Image(systemName: hoveringLanded == crew.number ? "play.fill" : "checkmark.circle.fill")
                    .font(.system(size: hoveringLanded == crew.number ? 7 : 9))
                    .foregroundStyle(
                        hoveringLanded == crew.number
                            ? Runway.green
                            : Runway.purple.opacity(0.75)
                    )
                    .frame(width: 15, height: 15)
                    .background(
                        Circle().fill(
                            hoveringLanded == crew.number
                                ? Runway.green.opacity(0.12)
                                : Color.clear
                        )
                    )
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .pointerCursor()
            .help("Bring this landed crew back up")
            .onHover { hoveringLanded = $0 ? crew.number : nil }

            copyButton(
                "\(crew.title) \(GitHubNumber.reference(crew.number))",
                help: "Copy issue title and number"
            ) {
                Text(crew.title)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.white.opacity(0.4))
                    .strikethrough(color: Color.white.opacity(0.22))
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            copyButton(GitHubNumber.reference(crew.number), help: "Copy issue number") {
                Text(verbatim: GitHubNumber.reference(crew.number))
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.26))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 7).fill(Color(white: 0.04)))
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 7))
        .contextMenu { crewMenu(crew) }
    }

    // MARK: Stood down

    /// Nothing running, nothing on screen but the issue it answers for.
    private func standingCard(_ crew: IssueLeg) -> some View {
        HStack(spacing: 10) {
            // No dot: the button already says whether this crew is up, and
            // two indicators for one state read as two states.
            activateButton(crew, up: false)

            VStack(alignment: .leading, spacing: 3) {
                copyButton(crewSubtitle(crew), help: "Copy issue number") {
                    Text(verbatim: crewSubtitle(crew))
                        .font(.system(size: 11))
                        .foregroundStyle(Color.white.opacity(0.42))
                }
                copyButton(
                    "\(crew.title) \(GitHubNumber.reference(crew.number))",
                    help: "Copy issue title and number"
                ) {
                    Text(crew.title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.72))
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 9).fill(Color(white: 0.055)))
        .overlay(
            RoundedRectangle(cornerRadius: 9)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 9))
        .onTapGesture { bringUp(crew) }
        .pointerCursor()
        .contextMenu { crewMenu(crew) }
    }

    /// A label that copies what it says. The flash is the whole feedback: a
    /// copy that needs explaining is a copy you cannot trust.
    private func copyButton(
        _ value: String,
        help: String,
        @ViewBuilder label: () -> some View
    ) -> some View {
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(value, forType: .string)
            copied = value
            Task {
                try? await Task.sleep(nanoseconds: 450_000_000)
                if copied == value { copied = nil }
            }
        } label: {
            label()
                .opacity(copied == value ? 0.45 : 1)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .pointerCursor()
        .help(help)
    }

    /// Right-click hands over the crew's conversation, so the same session can
    /// be reopened or addressed from anywhere else.
    @ViewBuilder
    private func crewMenu(_ crew: IssueLeg) -> some View {
        let repository = crewRepositoryName(crew)
        let session = AgentSessionLocator.resolve(
            boxID: FlightCrewSessions.boxID(
                rank: .crew,
                repository: repository,
                issue: crew.number
            ),
            workingDirectory: FlightCrewSessions.workingDirectory(for: repository),
            focusRepository: repository,
            focusIssueNumber: crew.number,
            issueSessionsEnabled: true
        )
        if let session {
            if let peer = AgentSessionLocator.peerName(for: session.sessionID) {
                Button("Copy agent name") { copy(peer) }
            }
            Button("Copy resume command") { copy(session.resumeCommand) }
            Button("Copy session ID") { copy(session.sessionID) }
            Divider()
        }
        Button("Copy issue link") { copy(crew.url.absoluteString) }
        Button("Open on GitHub") { NSWorkspace.shared.open(crew.url) }
    }

    private func copy(_ value: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }

    /// The repository a crew works in, named only as far as it is useful.
    private func crewHome(_ crew: IssueLeg) -> String {
        if let elsewhere = crew.repository {
            return String(elsewhere.split(separator: "/").last ?? "")
        }
        let flightURL = issues.issue(ws.flightNumber)?.url.pathComponents ?? []
        guard flightURL.count >= 3 else { return "" }
        return flightURL[flightURL.count - 3]
    }

    private func crewSubtitle(_ crew: IssueLeg) -> String {
        let home = crewHome(crew)
        let reference = GitHubNumber.reference(crew.number)
        return home.isEmpty ? reference : home + " " + reference
    }

    private func crewSession(_ crew: IssueLeg) -> String {
        let home = crewHome(crew)
        return home.isEmpty ? "crew-\(crew.number)" : "\(home)-\(crew.number)"
    }

    // MARK: Flying

    private func activeBox(_ crew: IssueLeg) -> some View {
        let isReading = reading == crew.number
        return VStack(spacing: 0) {
            HStack(spacing: 8) {
                // The control sits where the dot was, on both kinds of card.
                activateButton(crew, up: true)

                copyButton(
                    "\(crew.title) \(GitHubNumber.reference(crew.number))",
                    help: "Copy issue title and number"
                ) {
                    Text(crew.title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.9))
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                if crew.isClosed {
                    Text("LANDED")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundStyle(Runway.purple.opacity(0.85))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Runway.purple.opacity(0.14)))
                }

                copyButton(GitHubNumber.reference(crew.number), help: "Copy issue number") {
                    Text(verbatim: GitHubNumber.reference(crew.number))
                        .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Color.white.opacity(0.4))
                }
            }
            .padding(.horizontal, 11)
            .frame(height: 28)
            .background(RunwayTerminal.headerBar)
            .contextMenu { crewMenu(crew) }

            crewTerminal(crew)
                // The same room the pilot's terminal gets, so text never
                // runs into the box's edge.
                .padding(.horizontal, 8)
                .padding(.bottom, 6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 9))
        .overlay(
            RoundedRectangle(cornerRadius: 9)
                .stroke(
                    Color.white.opacity(isReading ? 0.18 : 0.1),
                    lineWidth: 1
                )
        )
        .contentShape(RoundedRectangle(cornerRadius: 9))
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.2)) { reading = crew.number }
        }
        .simultaneousGesture(
            // A click into the terminal itself is still a click on this crew.
            TapGesture().onEnded {
                withAnimation(.easeInOut(duration: 0.2)) { reading = crew.number }
            }
        )
    }

    @ViewBuilder
    private func crewTerminal(_ crew: IssueLeg) -> some View {
        if let repository = crewRepository(crew) {
            TerminalSurfaceView(
                boxID: FlightCrewSessions.boxID(
                    rank: .crew,
                    repository: repository,
                    issue: crew.number
                ),
                workspace: ws,
                config: FlightCrewSessions.config(
                    rank: .crew,
                    repository: repository,
                    issue: crew.number,
                    title: crew.title,
                    flight: ws.flightNumber,
                    reportsTo: pilotName
                )
            )
            .id("crew-\(repository)-\(crew.number)")
            .background(RunwayTerminal.body)
        } else {
            Color(white: 0.045)
        }
    }

    /// A crew works in its own repository when the flight reaches into one.
    private func crewRepository(_ crew: IssueLeg) -> String? {
        crew.repository ?? issues.repository
    }

    private var pilotName: String? {
        guard let repository = issues.repository, let flight = ws.flightNumber else { return nil }
        return FlightCrewSessions.sessionName(
            rank: .pilot,
            repository: repository,
            issue: flight,
            title: issues.issue(flight)?.title ?? ""
        )
    }

    /// What this crew is doing: green while it works, amber when it wants you.
    private func crewColour(_ crew: IssueLeg) -> Color {
        guard let repository = crewRepository(crew) else { return Color.white.opacity(0.3) }
        let id = FlightCrewSessions.boxID(rank: .crew, repository: repository, issue: crew.number)
        switch ws.agentStates[id] ?? .idle {
        case .needsAction: return Runway.amber
        case .running: return Runway.green
        default: return Color.white.opacity(0.3)
        }
    }

    /// The one control that matters on a card: bring this crew up, or stand it
    /// down and give the pane back.
    private func activateButton(_ crew: IssueLeg, up: Bool) -> some View {
        Button {
            if up { standDown(crew) } else { bringUp(crew) }
        } label: {
            Image(systemName: up ? "pause.fill" : "play.fill")
                .font(.system(size: 7))
                .foregroundStyle(up ? Color.white.opacity(0.5) : Runway.green)
                .frame(width: 15, height: 15)
                .background(
                    Circle().fill(up ? Color.white.opacity(0.08) : Runway.green.opacity(0.12))
                )
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .pointerCursor()
        .help(up ? "Pause this crew" : "Bring this crew up")
    }

    private func bringUp(_ crew: IssueLeg) {
        withAnimation(.easeInOut(duration: 0.22)) {
            deck.bringUp(crewRepositoryName(crew), crew.number, title: crew.title)
            reading = crew.number
        }
    }

    private func standDown(_ crew: IssueLeg) {
        withAnimation(.easeInOut(duration: 0.22)) {
            deck.standDown(crewRepositoryName(crew), crew.number, title: crew.title)
            // Standing down the one you were reading leaves no one chosen,
            // so the rest go back to equal rather than one being picked for
            // you.
            if reading == crew.number { reading = nil }
        }
    }
}

/// How the crews share the pane. A card keeps the height it asks for; every
/// point left over goes to the crews that are up, the one being read taking
/// two shares to the others' one. Nothing is guessed, so nothing is left
/// unclaimed at the bottom.
struct CrewAccordion: Layout {
    static let gap: CGFloat = 10
    static let minimumBox: CGFloat = 150

    let spacing: CGFloat
    let minimumBox: CGFloat

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        CGSize(width: proposal.width ?? 0, height: proposal.height ?? 0)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        guard !subviews.isEmpty else { return }
        let shares = subviews.map { $0[CrewShareKey.self] }
        let cardHeights = subviews.indices.map { index -> CGFloat in
            guard shares[index] == 0 else { return 0 }
            return subviews[index]
                .sizeThatFits(ProposedViewSize(width: bounds.width, height: nil))
                .height
        }
        let gaps = spacing * CGFloat(max(0, subviews.count - 1))
        let boxCount = shares.filter { $0 > 0 }.count
        let free = max(
            bounds.height - gaps - cardHeights.reduce(0, +),
            minimumBox * CGFloat(boxCount)
        )
        let totalShares = CGFloat(shares.reduce(0, +))

        var y = bounds.minY
        for (index, subview) in subviews.enumerated() {
            let height = shares[index] == 0
                ? cardHeights[index]
                : (totalShares > 0 ? free * CGFloat(shares[index]) / totalShares : 0)
            subview.place(
                at: CGPoint(x: bounds.minX, y: y),
                anchor: .topLeading,
                proposal: ProposedViewSize(width: bounds.width, height: height)
            )
            y += height + spacing
        }
    }
}

/// Zero for a card, which keeps its own height; otherwise the share of what
/// is left that this crew's box takes.
struct CrewShareKey: LayoutValueKey {
    static let defaultValue = 0
}


/// Holds the pane's backing view so a click monitor can ask where a click
/// landed. A class, because the view arrives after the struct is made.
@MainActor
final class PaneViewBox {
    weak var view: NSView?
}

/// An empty view whose only job is to hand its `NSView` to the box.
private struct PaneHitArea: NSViewRepresentable {
    let box: PaneViewBox

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        box.view = view
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        box.view = nsView
    }
}
