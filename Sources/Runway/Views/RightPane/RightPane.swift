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

    private var crews: [IssueLeg] {
        (issues.issue(ws.flightNumber)?.legs ?? []).filter { !$0.isClosed }
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
                if isUp(crew) {
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
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .clipped()
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.22)) { reading = nil }
        }
        .overlay {
            if crews.isEmpty { noCrews }
        }
        .background(Color.black)
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

    // MARK: Stood down

    /// Nothing running, nothing on screen but the issue it answers for.
    private func standingCard(_ crew: IssueLeg) -> some View {
        HStack(spacing: 10) {
            Circle()
                .strokeBorder(crewColour(crew).opacity(0.8), lineWidth: 1.2)
                .frame(width: 11, height: 11)

            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: crewSubtitle(crew))
                    .font(.system(size: 11))
                    .foregroundStyle(Color.white.opacity(0.42))
                Text(crew.title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.72))
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            activateButton(crew, up: false)
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
                Circle()
                    .fill(crewColour(crew))
                    .frame(width: 7, height: 7)
                    .shadow(color: crewColour(crew).opacity(0.7), radius: 4)

                Text(crew.title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.9))
                    .lineLimit(1)

                Spacer(minLength: 8)

                Text(verbatim: GitHubNumber.reference(crew.number))
                    .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.4))

                activateButton(crew, up: true)
            }
            .padding(.horizontal, 11)
            .frame(height: 28)
            .background(RunwayTerminal.headerBar)

            crewTerminal(crew)
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
            Image(systemName: up ? "stop.fill" : "play.fill")
                .font(.system(size: 8.5))
                .foregroundStyle(up ? Color.white.opacity(0.45) : Runway.green)
                .frame(width: 20, height: 20)
                .background(
                    Circle().fill(up ? Color.white.opacity(0.06) : Runway.green.opacity(0.12))
                )
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .pointerCursor()
        .help(up ? "Stand this crew down" : "Bring this crew up")
    }

    private func bringUp(_ crew: IssueLeg) {
        withAnimation(.easeInOut(duration: 0.22)) {
            deck.bringUp(crewRepositoryName(crew), crew.number)
            reading = crew.number
        }
    }

    private func standDown(_ crew: IssueLeg) {
        withAnimation(.easeInOut(duration: 0.22)) {
            deck.standDown(crewRepositoryName(crew), crew.number)
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
