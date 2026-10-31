import SwiftUI

/// The pilot's pane: the agent flying one flight on top, and everything that
/// flight is made of underneath.
///
/// Nothing here is wired to real data yet. The sample below is placeholder, so
/// the shape can be judged before a flight model exists.
struct MiddlePane: View {
    @Bindable var ws: Workspace
    @Bindable var issues: AssignedIssues
    @State private var pullRequests = PullRequests.shared
    @State private var closing = false
    @State private var askingToCloseWithoutEvidence = false
    /// The step copied a moment ago, so its card can flash.
    @State private var copiedStep: String?
    /// Whether the pointer is on the close button, which is the only time it
    /// shows its colour.
    @State private var hoveringState = false
    @State private var crewTab: PilotSeat = .pilot
    @State private var section: FlightSection = .issue
    /// How much of the pane the terminal takes, as a fraction.
    @State private var terminalShare: CGFloat = 0.52
    @State private var dragStartShare: CGFloat?
    /// Flights whose seats stay mounted, oldest first.
    @State private var visited: [Int] = []

    /// The card every part of this pane sits on.
    static let card = Color(white: 0.082)

    /// The issue being flown, if one is picked and still ours.
    private var flight: AssignedIssue? { issues.issue(ws.flightNumber) }

    var body: some View {
        GeometryReader { geo in
            let terminalHeight = max(140, min(geo.size.height - 180, geo.size.height * terminalShare))

            if flight == nil {
                nothingFlying
            } else {
            // One card holds the whole flight. The chrome is a slight grey,
            // and every terminal in it is pure black, so a running agent reads
            // as a hole cut in the card rather than another panel.
            VStack(spacing: 0) {
                flightHeader
                terminalArea
                    .frame(height: terminalHeight)
                sectionDivider(in: geo.size.height)
                sectionStrip
                sectionBody
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .background(Self.card)
            .clipShape(RoundedRectangle(cornerRadius: 13))
            .overlay(
                RoundedRectangle(cornerRadius: 13)
                    .stroke(Color.white.opacity(0.07), lineWidth: 1)
            )
            // The same room the crew cards get in the right pane, so the
            // three panes breathe alike.
            .padding(.horizontal, 7)
            .padding(.bottom, 7)
            // Clear of the window's top edge, where the left pane's own
            // heading already gives it room.
            .padding(.top, 16)
            }
        }
        .background(Color.black)
        .onAppear {
            keepMounted(ws.flightNumber)
            noteOpened(ws.flightNumber)
        }
        // The PRs tab was empty until the left pane's Pulls tab happened to
        // have been opened, because that is the only place that loaded them.
        .task(id: issues.repository) {
            guard let repository = issues.repository else { return }
            pullRequests.restore(repository: repository)
            await pullRequests.revalidate(repository: repository, minimumAge: 60)
        }
        .onChange(of: ws.flightNumber) { previous, number in
            keepMounted(number)
            noteLeft(previous)
            noteOpened(number)
        }
        .onDisappear { noteLeft(ws.flightNumber) }
    }

    private var nothingFlying: some View {
        VStack(spacing: 7) {
            Image(systemName: "airplane.departure")
                .font(.system(size: 17))
                .foregroundStyle(Color.white.opacity(0.16))
            Text("Pick an issue to fly")
                .font(.system(size: 12))
                .foregroundStyle(Color.white.opacity(0.3))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Header

    /// Where this flight stands, read once and used by everything that
    /// shows it.
    private var flightStatus: FlightStatus {
        FlightStatus.of(
            closed: flight?.isClosed == true,
            steps: IssueBody.steps("Progress", in: flight?.body ?? "")
        )
    }

    private var flightHeader: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 7) {
                Text("FLIGHT")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.3))
                    .tracking(0.8)
                Text(verbatim: GitHubNumber.reference(flight?.number ?? 0))
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Runway.teal.opacity(0.9))
                Spacer(minLength: 8)
                statusChip(flightStatus)
            }

            Text(flight?.title ?? "")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.94))
                .lineLimit(2)

            legsBar
        }
        .padding(.horizontal, 14)
        .padding(.top, 14)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        // The card's head wears the flight's own state and fades back into
        // the grey, so where a flight stands reads from across the room and
        // not only from its chip.
        .background(
            LinearGradient(
                colors: [
                    flightStatus.color.opacity(0.20),
                    flightStatus.color.opacity(0.07),
                    Color.clear,
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .allowsHitTesting(false)
        )
    }

    /// The flight as a route: the legs behind it flown in green, the aircraft
    /// where it is now, the legs ahead in grey.
    private var legsBar: some View {
        let legs = flight?.legs ?? []
        let landed = flight?.isClosed == true
        // A landed flight has arrived, whatever its crews say: the run is
        // flown end to end, and drawn in the colour of closed.
        let flown = landed ? legs.count : legs.filter(\.isClosed).count
        let trail = landed ? Runway.purple : Runway.green
        return HStack(spacing: 4) {
            Circle()
                .fill(trail.opacity(0.9))
                .frame(width: 5, height: 5)

            // A route reads left to right: what is flown, then the aircraft,
            // then what is ahead. Colouring each segment by its own crew put
            // a landed crew wherever it happened to sit in the list, so the
            // bar showed green behind grey. Position says it, not identity.
            ForEach(0..<legs.count, id: \.self) { index in
                if index == flown {
                    Image(systemName: "airplane")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Runway.teal)
                }
                legSegment(done: index < flown, colour: trail)
            }

            if legs.isEmpty {
                Capsule()
                    .fill(landed ? trail : Color.white.opacity(0.14))
                    .frame(height: 3)
            }

            if landed || (!legs.isEmpty && flown == legs.count) {
                Image(systemName: "airplane.arrival")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(trail)
            }

            Circle()
                .fill(landed ? trail.opacity(0.9) : Color.clear)
                .overlay(
                    Circle().strokeBorder(
                        landed ? Color.clear : Color.white.opacity(0.28),
                        lineWidth: 1
                    )
                )
                .frame(width: 5, height: 5)

            Text(legs.isEmpty ? "no crews yet" : "\(flown)/\(legs.count) crews")
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(Color.white.opacity(0.32))
                .fixedSize()
                .padding(.leading, 2)
        }
    }

    private func legSegment(done: Bool, colour: Color) -> some View {
        Capsule()
            .fill(done ? colour : Color.white.opacity(0.14))
            .frame(height: 3)
    }

    private func statusChip(_ status: FlightStatus) -> some View {
        Text(status.label)
            .font(.system(size: 8.5, weight: .bold, design: .monospaced))
            .foregroundStyle(status.color)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Capsule().fill(status.color.opacity(0.12)))
    }

    // MARK: Pilot and copilot

    private var seatStrip: some View {
        HStack(spacing: 4) {
            ForEach(PilotSeat.allCases) { seat in
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { crewTab = seat }
                } label: {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(seatColour(seat))
                            .frame(width: 5, height: 5)
                        Text(seat.rawValue)
                            .font(.system(
                                size: 10.5,
                                weight: crewTab == seat ? .semibold : .medium,
                                design: .monospaced
                            ))
                    }
                    .foregroundStyle(
                        crewTab == seat ? Color.white.opacity(0.88) : Color.white.opacity(0.4)
                    )
                    .padding(.horizontal, 10)
                    .frame(height: 22)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(crewTab == seat ? Color.white.opacity(0.08) : .clear)
                    )
                    .contentShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .pointerCursor()
            }
        }
        .padding(.leading, 190)
        .padding(.trailing, 10)
        .padding(.top, 8)
        .padding(.bottom, 20)
        // A patch of black around the buttons, not a band across the top: it
        // fades away downwards and leftwards into whatever the agent printed.
        // It takes no clicks and no drops of its own: it covers a wide strip
        // of the terminal, and a file dropped onto that strip has to reach
        // the terminal underneath.
        .background(
            LinearGradient(
                colors: [Color.black, Color.black, Color.black.opacity(0)],
                startPoint: .top,
                endPoint: .bottom
            )
            .mask(
                LinearGradient(
                    colors: [
                        Color.black.opacity(0),
                        Color.black.opacity(0.55),
                        Color.black,
                        Color.black,
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            // The fade takes no clicks and no drops of its own: it covers a
            // wide strip of the terminal, and a file dropped on that strip
            // has to reach the terminal underneath.
            .allowsHitTesting(false)
        )
    }

    @ViewBuilder
    /// What the seat is doing: green while it works, amber when it wants you.
    private func seatColour(_ seat: PilotSeat) -> Color {
        guard let flight, let repository = issues.repository else {
            return Color.white.opacity(0.22)
        }
        let id = FlightCrewSessions.boxID(
            rank: seat == .pilot ? .pilot : .copilot,
            repository: repository,
            issue: flight.number
        )
        switch ws.agentStates[id] ?? .idle {
        case .needsAction: return Runway.amber
        case .running: return Runway.green
        default: return Color.white.opacity(0.22)
        }
    }

    /// Every flight you have opened keeps its seats on screen, hidden.
    ///
    /// Leaving a flight must not take its terminals out of the view
    /// hierarchy. Holding the session alive while SwiftUI tore the view down
    /// and built a new one meant re-attaching a libghostty surface through
    /// that cycle, which wedged the app when you left one mid-start and came
    /// back. So nothing is ever unmounted: a flight you leave only goes to
    /// zero opacity, exactly as the copilot seat always has.
    /// One flight on screen at a time. Its seats' views are reparented, not
    /// rebuilt, so leaving a flight neither kills the agent nor leaves a
    /// second Metal surface drawing behind it.
    private static let flightsKeptMounted = 1

    /// The flight on screen plus the ones left mounted behind it. Computed
    /// rather than read from state, so the flight you are on is mounted on
    /// the very first pass, before any `onAppear` has run.
    private var mounted: [Int] {
        var list = visited
        if let number = ws.flightNumber, !list.contains(number) { list.append(number) }
        return list
    }

    private var terminalArea: some View {
        Group {
        if let repository = issues.repository, !mounted.isEmpty {
            ZStack {
                ForEach(mounted, id: \.self) { number in
                    if let seen = issues.issue(number) {
                        let showing = number == ws.flightNumber
                        ForEach(PilotSeat.allCases) { seat in
                            seatTerminal(
                                seat,
                                flight: seen,
                                repository: repository,
                                visible: showing && crewTab == seat
                            )
                                // Room to breathe for the one terminal you
                                // read most. Here rather than in the shared
                                // terminal theme, so a crew box and the ATC
                                // panel keep their tight fit.
                                .padding(.horizontal, 9)
                                .padding(.vertical, 7)
                                .opacity(showing && crewTab == seat ? 1 : 0)
                                .allowsHitTesting(showing && crewTab == seat)
                        }
                    }
                }
            }
            .background(Color.black)
            .overlay(alignment: .topTrailing) { seatStrip }
            .clipShape(RoundedRectangle(cornerRadius: 9))
            .padding(.horizontal, 12)
        } else {
            RoundedRectangle(cornerRadius: 9)
                .fill(Color.black)
                .padding(.horizontal, 12)
        }
        }
    }

    /// When the flight on screen was opened, so leaving it can say how long
    /// it held your attention.
    @MainActor private static var openedAt: [Int: Date] = [:]

    private func noteOpened(_ number: Int?) {
        guard let number, let flight = issues.issue(number) else { return }
        Self.openedAt[number] = Date()
        ActivityLog.flightOpened(
            number,
            title: flight.title,
            repository: issues.repository ?? ""
        )
    }

    private func noteLeft(_ number: Int?) {
        guard let number, let since = Self.openedAt.removeValue(forKey: number) else { return }
        let seconds = Int(Date().timeIntervalSince(since))
        guard seconds >= 5 else { return }
        ActivityLog.flightLeft(
            number,
            title: issues.issue(number)?.title ?? "",
            repository: issues.repository ?? "",
            seconds: seconds
        )
    }

    /// Remember this flight's seats, and let the oldest go once there are
    /// more than the pane keeps. A flight whose agent is mid-turn, or waiting
    /// on you, is never the one dropped.
    private func keepMounted(_ number: Int?) {
        guard let number else { return }
        if let already = visited.firstIndex(of: number) {
            visited.remove(at: already)
        }
        visited.append(number)
        while visited.count > Self.flightsKeptMounted {
            let droppable = visited.dropLast().first { candidate in
                guard let repository = issues.repository else { return true }
                return !PilotSeat.allCases.contains { seat in
                    TerminalSessionPool.isBusy(
                        FlightCrewSessions.boxID(
                            rank: seat == .pilot ? .pilot : .copilot,
                            repository: repository,
                            issue: candidate
                        )
                    )
                }
            }
            guard let going = droppable, let at = visited.firstIndex(of: going) else { break }
            visited.remove(at: at)
        }
    }

    private func seatTerminal(
        _ seat: PilotSeat,
        flight: AssignedIssue,
        repository: String,
        visible: Bool
    ) -> some View {
        let rank: AgentRank = seat == .pilot ? .pilot : .copilot
        return TerminalSurfaceView(
            boxID: FlightCrewSessions.boxID(
                rank: rank,
                repository: repository,
                issue: flight.number
            ),
            workspace: ws,
            isVisible: visible,
            config: FlightCrewSessions.config(
                rank: rank,
                repository: repository,
                issue: flight.number,
                title: flight.title,
                flight: flight.number,
                reportsTo: "you"
            )
        )
        .id("\(rank.rawValue)-\(repository)-\(flight.number)")
        .background(RunwayTerminal.body)
    }

    /// Drag to give the terminal more of the pane, or less.
    private func sectionDivider(in height: CGFloat) -> some View {
        // No line: the black of the terminal already ends where the card
        // resumes. The band is still here to drag.
        Color.clear
            .frame(height: 14)
            .contentShape(Rectangle())
        .onHover { hovering in
            if hovering { NSCursor.resizeUpDown.set() } else { NSCursor.arrow.set() }
        }
        .gesture(
            // Global, not local: a local drag measures against the divider
            // itself, and the divider moves as you drag it, so the reading
            // feeds back into the next frame and the pane shakes.
            DragGesture(coordinateSpace: .global)
                .onChanged { value in
                    let start = dragStartShare ?? terminalShare
                    dragStartShare = start
                    guard height > 0 else { return }
                    terminalShare = min(max(start + value.translation.height / height, 0.2), 0.8)
                }
                .onEnded { _ in dragStartShare = nil }
        )
    }

    // MARK: Sections

    private var sectionStrip: some View {
        HStack(spacing: 0) {
            ForEach(FlightSection.allCases) { tab in
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { section = tab }
                } label: {
                    Text(tab.rawValue)
                        .font(.system(
                            size: 10,
                            weight: section == tab ? .semibold : .medium,
                            design: .monospaced
                        ))
                        .foregroundStyle(
                            section == tab ? Color.white.opacity(0.88) : Color.white.opacity(0.38)
                        )
                        .padding(.vertical, 5)
                        .frame(maxWidth: .infinity)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(section == tab ? Color.white.opacity(0.08) : .clear)
                        )
                        .contentShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .pointerCursor()
            }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.04)))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.06), lineWidth: 1))
        .padding(.horizontal, 12)
        .padding(.bottom, 10)
    }

    @ViewBuilder
    private var sectionBody: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                switch section {
                case .issue: issueSection
                case .pulls: pullsSection
                case .slides: slidesSection
                case .thread: threadSection
                }
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 16)
        }
        .contentMargins(.vertical, 0, for: .scrollContent)
        .scrollIndicators(.hidden)
        .safeAreaInset(edge: .bottom, spacing: 0) { flightBar }
    }

    /// The two moves that are always available, whichever tab you are on:
    /// read the issue where it lives, and close it when it has landed.
    @ViewBuilder
    private var flightBar: some View {
        if let flight {
            HStack(spacing: 8) {
                Button {
                    NSWorkspace.shared.open(flight.url)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.up.forward.square")
                            .font(.system(size: 11, weight: .medium))
                        Text("Open on GitHub")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundStyle(Color.white.opacity(0.6))
                    .frame(maxWidth: .infinity)
                    .frame(height: 28)
                    .background(RoundedRectangle(cornerRadius: 7).fill(Color(white: 0.13)))
                    .overlay(
                        RoundedRectangle(cornerRadius: 7)
                            .stroke(Color.white.opacity(0.1), lineWidth: 1)
                    )
                    .contentShape(RoundedRectangle(cornerRadius: 7))
                }
                .buttonStyle(.plain)
                .pointerCursor()
                .help("Open this issue on GitHub")

                stateButton(closed: flight.isClosed)
            }
            .alert(
                "This flight has no walkthrough",
                isPresented: $askingToCloseWithoutEvidence
            ) {
                Button("Close anyway") {
                    closing = true
                    Task {
                        await issues.setClosed(true, issue: flight.number)
                        closing = false
                    }
                }
                Button("Not yet", role: .cancel) {}
            } message: {
                Text(
                    "Neither this flight nor its crews saved any slides, so "
                    + "there is no evidence of what shipped. Ask the pilot "
                    + "for a walkthrough first, or close it anyway."
                )
            }
            .padding(.horizontal, 14)
            .padding(.top, 28)
            .padding(.bottom, 10)
            // No bar, no line: the buttons float, and what scrolls under them
            // fades into the card rather than being cut off by an edge.
            .background(
                LinearGradient(
                    colors: [
                        Self.card.opacity(0),
                        Self.card.opacity(0.75),
                        Self.card,
                        Self.card,
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        }
    }

    /// The legs, what each waits on, and what only you can answer.
    private var issueSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionLabel("PROGRESS")
            // The pilot's own checklist, kept in the issue body. Read down
            // the page, the way a checklist is written: the sideways strip
            // cut every step after the third in half and hid the rest.
            let steps = IssueBody.steps("Progress", in: flight?.body ?? "")
            if steps.isEmpty {
                Text("The pilot has not written a checklist for this flight yet.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Color.white.opacity(0.3))
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(steps.enumerated()), id: \.element.id) { index, step in
                        stepCard(step, number: index + 1)
                    }
                }
            }

            sectionLabel("ACCEPTANCE")
            let acceptance = IssueBody.steps("Acceptance", in: flight?.body ?? "")
            VStack(alignment: .leading, spacing: 5) {
                if acceptance.isEmpty {
                    Text("This issue says nothing about what done looks like.")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Color.white.opacity(0.3))
                }
                ForEach(acceptance) { line in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Image(systemName: line.done ? "checkmark.square.fill" : "square")
                            .font(.system(size: 9))
                            .foregroundStyle(
                                line.done ? Runway.green.opacity(0.8) : Color.white.opacity(0.22)
                            )
                        MarkdownText(text: line.text)
                            .font(.system(size: 12))
                            .foregroundStyle(Color.white.opacity(line.done ? 0.45 : 0.72))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

        }
    }


    private func stepCard(_ step: IssueBody.Step, number: Int) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: step.done ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 10))
                .foregroundStyle(step.done ? Runway.green : Color.white.opacity(0.25))
                .padding(.top, 1)
            Text("\(number)")
                .font(.system(size: 9.5, design: .monospaced))
                .foregroundStyle(Color.white.opacity(0.32))
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 4) {
            MarkdownText(text: step.label)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(Color.white.opacity(step.done ? 0.45 : 0.85))
                .strikethrough(step.done, color: Color.white.opacity(0.3))
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            // The blocker belongs to the step, not to a list of its own.
            if let needs = step.needs, !step.done {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.system(size: 8.5))
                    MarkdownText(text: needs, tint: AgentState.needsAction.color)
                        .font(.system(size: 10))
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .foregroundStyle(AgentState.needsAction.color.opacity(0.85))
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            }

            Spacer(minLength: 0)
        }
        .padding(9)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.white.opacity(copiedStep == step.text ? 0.09 : 0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.white.opacity(step.done ? 0.06 : 0.11), lineWidth: 1)
        )
        // One step, not the whole checklist. A card is the smallest thing
        // worth quoting into Slack or a message to a crew.
        .contentShape(RoundedRectangle(cornerRadius: 8))
        .onTapGesture { copyStep(step) }
        .pointerCursor()
        .help("Copy this step")
        .contextMenu {
            Button("Copy step") { copyStep(step) }
            if step.needs != nil {
                Button("Copy what it waits on") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(step.needs ?? "", forType: .string)
                }
            }
        }
    }

    /// Copy one step's own words, and flash the card so the copy is visible.
    private func copyStep(_ step: IssueBody.Step) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(step.label, forType: .string)
        copiedStep = step.text
        Task {
            try? await Task.sleep(nanoseconds: 450_000_000)
            if copiedStep == step.text { copiedStep = nil }
        }
    }

    /// Close the flight's issue once it has landed, or put it back in the air.
    private func stateButton(closed flightClosed: Bool) -> some View {
        Button {
            guard let number = flight?.number, !closing else { return }
            // A flight lands with its evidence. Closing one that never made
            // a walkthrough is allowed, but not by accident.
            if !flightClosed, slideSets.isEmpty {
                askingToCloseWithoutEvidence = true
                return
            }
            closing = true
            Task {
                await issues.setClosed(!flightClosed, issue: number)
                closing = false
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: closing
                    ? "hourglass"
                    : (flightClosed ? "arrow.counterclockwise.circle" : "checkmark.circle"))
                    .font(.system(size: 11, weight: .medium))
                Text(flightClosed ? "Reopen issue" : "Close issue")
                    .font(.system(size: 11, weight: .medium))
            }
            // Quiet until you reach for it. Closing a flight is the one
            // irreversible thing on this bar, so it should not sit there
            // coloured, competing with the work above it.
            .foregroundStyle(
                hoveringState
                    ? (flightClosed ? Runway.green : Runway.purple)
                    : Color.white.opacity(0.6)
            )
            .frame(maxWidth: .infinity)
            .frame(height: 28)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(Self.card)
                    .overlay(
                        RoundedRectangle(cornerRadius: 7)
                            .fill(
                                hoveringState
                                    ? (flightClosed ? Runway.green : Runway.purple).opacity(0.14)
                                    : Color.white.opacity(0.05)
                            )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .stroke(
                        hoveringState
                            ? (flightClosed ? Runway.green : Runway.purple).opacity(0.28)
                            : Color.white.opacity(0.1),
                        lineWidth: 1
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .pointerCursor()
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.14)) { hoveringState = hovering }
        }
    }

    /// Every PR of the flight, drawn the way the Pulls tab draws them.
    private var pullsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            if flightPulls.isEmpty {
                sectionLabel("PULL REQUESTS")
                Text("No pull request names this flight or its crews yet.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Color.white.opacity(0.3))
            } else {
                PullRequestList(
                    pullRequests: flightPulls,
                    scope: "flight-\(flight?.number ?? 0)"
                )
            }
        }
    }

    /// The pull requests of this flight, found two ways.
    ///
    /// The branch convention names the issue, so a branch ending in the
    /// flight's number or a crew's is ours. That only works for branches we
    /// wrote: a teammate's PR under review carries no number of ours. So a
    /// number the flight's own text points at counts too, which is how
    /// Sindri's #17337 and #17338 belong to Tap to Pay.
    private var flightPulls: [RepositoryPullRequest] {
        guard let flight else { return [] }
        let issues = Set([flight.number] + flight.legs.map(\.number))
        let mentioned = Self.referenced(in: flight.body)
        return pullRequests.pullRequests
            .filter { pull in
                if let owner = BranchIssue.number(in: pull.headRefName), issues.contains(owner) {
                    return true
                }
                return mentioned.contains(pull.number)
            }
            .sorted { $0.number > $1.number }
    }

    /// Every `#1234` an issue's text points at.
    static func referenced(in body: String) -> Set<Int> {
        var found: Set<Int> = []
        var digits = ""
        var afterHash = false
        for character in body {
            if character == "#" {
                afterHash = true
                digits = ""
                continue
            }
            if afterHash, character.isNumber {
                digits.append(character)
                continue
            }
            if afterHash, let number = Int(digits), number > 0 { found.insert(number) }
            afterHash = false
            digits = ""
        }
        if afterHash, let number = Int(digits), number > 0 { found.insert(number) }
        return found
    }

    private func stateLabel(_ pull: RepositoryPullRequest) -> String {
        if pull.isMerged { return "MERGED" }
        if !pull.isOpen { return "CLOSED" }
        return pull.isDraft ? "DRAFT" : "OPEN"
    }

    private func stateColour(_ pull: RepositoryPullRequest) -> Color {
        if pull.isMerged { return Runway.purple }
        if !pull.isOpen { return Color.white.opacity(0.38) }
        return pull.isDraft ? Runway.amber : Runway.green
    }

    private func checkChip(_ state: CheckState) -> some View {
        Text(state.label)
            .font(.system(size: 8, weight: .bold, design: .monospaced))
            .foregroundStyle(state.color)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(Capsule().fill(state.color.opacity(0.12)))
    }

    /// The evidence this flight has produced: whatever a walkthrough left in
    /// this issue's folder.
    /// A flight's evidence is its own and its crews'. A crew photographs
    /// what it verified; the pilot's set is the whole flight's statement.
    /// Showing only the flight's own folder hid every crew's work.
    private struct SlideSet: Identifiable {
        let issue: Int
        let title: String
        let slides: [URL]
        var id: Int { issue }
    }

    private var slideSets: [SlideSet] {
        guard let flight else { return [] }
        var sets: [SlideSet] = []
        let own = WalkthroughSlides.forIssue(flight.number)
        if !own.isEmpty {
            sets.append(SlideSet(issue: flight.number, title: "This flight", slides: own))
        }
        for crew in flight.legs {
            let slides = WalkthroughSlides.forIssue(crew.number)
            guard !slides.isEmpty else { continue }
            sets.append(SlideSet(issue: crew.number, title: crew.title, slides: slides))
        }
        return sets
    }

    private var slidesSection: some View {
        let sets = slideSets
        return VStack(alignment: .leading, spacing: 14) {
            sectionLabel("WALKTHROUGH")

            if sets.isEmpty {
                Text("No walkthrough slides for this flight or its crews yet.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Color.white.opacity(0.3))
            }

            ForEach(sets) { set in
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Text(set.title)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Color.white.opacity(0.68))
                            .lineLimit(1)
                        Text(verbatim: GitHubNumber.reference(set.issue))
                            .font(.system(size: 9, weight: .semibold, design: .monospaced))
                            .foregroundStyle(Color.white.opacity(0.3))
                        Spacer(minLength: 8)
                        Button {
                            NSWorkspace.shared.open(set.slides[0].deletingLastPathComponent())
                        } label: {
                            Text("Open folder")
                                .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                                .foregroundStyle(Runway.teal.opacity(0.85))
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(Capsule().fill(Runway.teal.opacity(0.1)))
                                .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .pointerCursor()
                    }

                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 104), spacing: 8)],
                        spacing: 8
                    ) {
                        ForEach(set.slides, id: \.self) { slide in
                            Button {
                                NSWorkspace.shared.open(slide)
                            } label: {
                                VStack(alignment: .leading, spacing: 5) {
                                    slideThumbnail(slide)
                                    Text(slide.deletingPathExtension().lastPathComponent)
                                        .font(.system(size: 9, design: .monospaced))
                                        .foregroundStyle(Color.white.opacity(0.4))
                                        .lineLimit(1)
                                }
                            }
                            .buttonStyle(.plain)
                            .pointerCursor()
                        }
                    }
                }
            }
        }
    }

    private func slideThumbnail(_ slide: URL) -> some View {
        Group {
            if let image = SlideThumbnails.image(for: slide) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Color(white: 0.08)
                    .overlay(
                        Image(systemName: "photo")
                            .font(.system(size: 14))
                            .foregroundStyle(Color.white.opacity(0.16))
                    )
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.white.opacity(0.07), lineWidth: 1)
        )
    }

    private var threadSection: some View {
        let entries = IssueBody.conversation("Situation Development", in: flight?.body ?? "")
        let home = IssueBody.homeThread("Situation Development", in: flight?.body ?? "")
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                sectionLabel("SITUATION")
                Spacer(minLength: 8)
                if let home {
                    Button {
                        NSWorkspace.shared.open(home)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.up.forward.app")
                                .font(.system(size: 9, weight: .semibold))
                            Text(threadButtonTitle)
                                .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                        }
                        .foregroundStyle(Runway.teal.opacity(0.85))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Runway.teal.opacity(0.1)))
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .pointerCursor()
                    .help("Open this flight's thread where it lives")
                }
            }

            if entries.isEmpty {
                Text("This issue keeps no conversation log yet.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Color.white.opacity(0.3))
            }

            // One rail down the whole log, not a segment per entry. The
            // segments left a gap at every row boundary, which read as a
            // broken line rather than a thread.
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                    if let day = entry.day, day != entries[safe: index - 1]?.day {
                        HStack(spacing: 9) {
                            Rectangle()
                                .fill(Color.white.opacity(index > 0 ? 0.08 : 0))
                                .frame(width: 1, height: 22)
                                .frame(width: 5)
                            Text(day)
                                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                                .foregroundStyle(Color.white.opacity(0.32))
                                .tracking(0.6)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    HStack(alignment: .top, spacing: 9) {
                        VStack(spacing: 0) {
                            // The 5 points above a dot are rail too, for
                            // every entry but the first. Leaving them blank
                            // is what broke the line under each name.
                            Rectangle()
                                .fill(Color.white.opacity(index > 0 ? 0.08 : 0))
                                .frame(width: 1, height: 5)
                            Circle()
                                .fill(Color.white.opacity(0.28))
                                .frame(width: 5, height: 5)
                            if index < entries.count - 1 {
                                Rectangle()
                                    .fill(Color.white.opacity(0.08))
                                    .frame(width: 1)
                                    .frame(maxHeight: .infinity)
                            }
                        }
                        .frame(width: 5)

                        VStack(alignment: .leading, spacing: 3) {
                            Button {
                                if let link = entry.link { NSWorkspace.shared.open(link) }
                            } label: {
                                Text(entry.who)
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(Runway.teal.opacity(0.85))
                            }
                            .buttonStyle(.plain)
                            .pointerCursor()
                            MarkdownText(text: entry.said)
                                .font(.system(size: 11.5))
                                .foregroundStyle(Color.white.opacity(0.78))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.bottom, index < entries.count - 1 ? 10 : 0)

                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

        }
    }

    /// What the button says: where this flight's conversation lives.
    private var threadButtonTitle: String {
        let channel = IssueBody.homeChannel("Situation Development", in: flight?.body ?? "")
        guard let channel, !channel.isEmpty else { return "Open thread" }
        return "Open thread in \(channel)"
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .semibold, design: .monospaced))
            .foregroundStyle(Color.white.opacity(0.3))
            .tracking(0.8)
    }
}

// MARK: Palette

enum Runway {
    static let green = Color(red: 0.18, green: 0.78, blue: 0.38)
    static let amber = Color(red: 0.94, green: 0.62, blue: 0.20)
    static let purple = Color(red: 0.64, green: 0.42, blue: 0.94)
    static let teal = Color(red: 0.45, green: 0.82, blue: 0.78)
}

// MARK: The pane's vocabulary

enum PilotSeat: String, CaseIterable, Identifiable {
    case pilot = "pilot"
    case copilot = "copilot"

    var id: String { rawValue }
}

enum FlightSection: String, CaseIterable, Identifiable {
    case issue = "Issue"
    case pulls = "Pulls"
    case slides = "Walkthrough"
    case thread = "Thread"

    var id: String { rawValue }
}

enum CheckState {
    case passing
    case running
    case failing

    var label: String {
        switch self {
        case .passing: "CHECKS OK"
        case .running: "CHECKS RUNNING"
        case .failing: "CHECKS FAILED"
        }
    }

    var color: Color {
        switch self {
        case .passing: Runway.green
        case .running: Runway.amber
        case .failing: Color(red: 0.94, green: 0.36, blue: 0.36)
        }
    }
}
