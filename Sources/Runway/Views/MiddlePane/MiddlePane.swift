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
    /// The step copied a moment ago, so its card can flash.
    @State private var copiedStep: String?
    @AppStorage(SettingsKey.pilotTerminalPadding) private var pilotPadding = 9
    /// Whether the pointer is on the close button, which is the only time it
    /// shows its colour.
    @State private var crewTab: PilotSeat = .pilot
    /// How much of the pane the terminal takes, as a fraction. Remembered,
    /// because where you set the split is a preference, not a session.
    @AppStorage(SettingsKey.terminalShare) private var storedShare = 0.52
    @State private var dragShare: CGFloat?
    /// How many pulls the board is showing; the rest are behind the button
    /// at its foot.
    @State private var pullsShown = 13
    /// The slow pulse the boarding stop wears. One timer for the pane, not
    /// one per row.
    @State private var blink = false
    /// Flights whose seats stay mounted, oldest first.
    @State private var visited: [Int] = []

    /// The card every part of this pane sits on.
    static let card = Color(white: 0.082)

    /// The issue being flown, if one is picked and still ours.
    private var flight: AssignedIssue? { issues.issue(ws.flightNumber) }

    var body: some View {
        GeometryReader { geo in
            // The terminal keeps at least 120 points, and the boards under
            // it never fall below 160, whatever the window is doing.
            let terminalHeight = max(120, min(geo.size.height - 160, geo.size.height * terminalShare))

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
                sectionBody
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            // The foot wears the flight's state the way the head does, so
            // the card is bracketed in its own colour. It sits on the card,
            // behind the box, now that the strip is the box's floor.
            .background(alignment: .bottom) {
                LinearGradient(
                    colors: [
                        Color.clear,
                        flightStatus.color.opacity(0.07),
                        flightStatus.color.opacity(0.20),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 110)
                .allowsHitTesting(false)
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
        .task {
            // The board's own blink, a step either side of a second and a
            // half, the way a departures board flips.
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 800_000_000)
                blink.toggle()
            }
        }
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

    /// The flight's own board header: its number in flap tiles, its name in
    /// caps, where it stands at the far end, and the repository and class
    /// under it.
    private var flightHeader: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 10) {
                FlapNumber(number: flight?.number ?? 0)
                Text((flight?.title ?? "").uppercased())
                    .font(.mono(14, .medium))
                    .tracking(0.8)
                    .foregroundStyle(Board.ink)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 8)
                Text(flightStatus.label)
                    .font(.mono(8.5))
                    .tracking(1.6)
                    .foregroundStyle(statusInk)
                    .fixedSize()
            }

            HStack(spacing: 14) {
                Text(shortRepository.uppercased())
                    .font(.mono(8.5))
                    .tracking(1.5)
                    .foregroundStyle(Board.dim)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    Text("CLASS")
                        .font(.mono(8.5))
                        .tracking(1.5)
                        .foregroundStyle(Board.dim)
                    Text(headerPriority.label)
                        .font(.mono(8.5, .semibold))
                        .tracking(1.5)
                        .foregroundStyle(headerPriority.colour)
                }
                Spacer(minLength: 0)
            }

            legsBar
                .padding(.top, 5)
        }
        .padding(.horizontal, 14)
        .padding(.top, 14)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        // Left as it was: the card's head wears the flight's own state and
        // fades back into the grey.
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

    /// Just the clone's name, the way the cards print it.
    private var shortRepository: String {
        let full = issues.repository ?? ""
        return full.split(separator: "/").last.map(String.init) ?? full
    }

    /// The board's three, rather than the chip's: grey waiting, teal in the
    /// air, purple once down.
    private var statusInk: Color {
        switch flightStatus {
        case .scheduled: Board.muted
        case .onAir: Board.teal
        case .landed: Board.purple
        }
    }

    /// The gate class, read from the same board the cards read.
    private var headerPriority: (label: String, colour: Color) {
        guard let flight, let repository = issues.repository,
              let level = FlightBoard.shared.priority(flight.number, in: repository) else {
            return ("P-", Board.faint)
        }
        return (FlightPriority.label(level), FlightPriority.color(level))
    }

    /// The flight as a route: one segment a leg, filling teal as each lands,
    /// a ring at the gate, and the count at the end.
    private var legsBar: some View {
        let steps = IssueBody.steps("Progress", in: flight?.body ?? "")
            .filter { !$0.isLanding }
        let landed = flight?.isClosed == true
        let flown = landed ? steps.count : steps.filter(\.done).count
        let trail = landed ? Board.purple : Board.teal
        return HStack(spacing: 8) {
            Image(systemName: "airplane")
                .font(.system(size: 10))
                .foregroundStyle(trail)

            if steps.isEmpty {
                Capsule().fill(Board.line).frame(height: 3)
            } else {
                ForEach(0..<steps.count, id: \.self) { index in
                    Capsule()
                        .fill(Board.line)
                        .frame(height: 3)
                        .overlay(alignment: .leading) {
                            if index < flown { Capsule().fill(trail) }
                        }
                }
            }

            Circle()
                .strokeBorder(landed ? trail : Board.faint, lineWidth: 1.5)
                .background(Circle().fill(landed ? trail : Color.clear))
                .frame(width: 7, height: 7)

            Text(verbatim: steps.isEmpty ? "NO LEGS" : "\(flown)/\(steps.count) LEGS")
                .font(.mono(8))
                .tracking(1.4)
                .foregroundStyle(Board.dim)
                .fixedSize()
        }
    }

    // MARK: Pilot and copilot

    /// Pilot or copilot, as two plain options rather than a boxed control.
    /// A dot before each says what that seat is doing; the one you are
    /// reading wears a pill.
    private var seatStrip: some View {
        HStack(spacing: 4) {
            ForEach(PilotSeat.allCases) { seat in
                SeatButton(
                    title: seat.rawValue,
                    active: crewTab == seat,
                    dot: seatColour(seat)
                ) {
                    withAnimation(.easeInOut(duration: 0.15)) { crewTab = seat }
                }
            }
        }
        .padding(.leading, 190)
        .padding(.trailing, 10)
        .padding(.top, 8)
        .padding(.bottom, 20)
        // A patch of black around the buttons, not a band across the top: it
        // fades away downwards and leftwards into whatever the agent printed.
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
            return Color(red: 0.227, green: 0.235, blue: 0.251)
        }
        let id = FlightCrewSessions.boxID(
            rank: seat == .pilot ? .pilot : .copilot,
            repository: repository,
            issue: flight.number
        )
        switch ws.agentStates[id] ?? .idle {
        case .needsAction: return Board.amber
        case .running: return Board.seatLive
        default: return Color(red: 0.227, green: 0.235, blue: 0.251)   // #3a3c40
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
        // Pilots held up from outside the window. An agent that wants to
        // brief seven flights cannot click seven cards, so `runway pilot up`
        // puts them here and their seats start behind whatever is on screen.
        if let repository = issues.repository {
            for number in PilotDeck.shared.flights(in: repository)
            where !list.contains(number) && issues.issue(number) != nil {
                list.append(number)
            }
        }
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
                                .padding(.horizontal, CGFloat(pilotPadding))
                                .padding(.vertical, CGFloat(max(0, pilotPadding - 2)))
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
                // A pilot held up on purpose is never the one dropped.
                if PilotDeck.shared.isUp(repository, candidate) { return false }
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
    /// The gap between the terminal and the boards is the handle. A short
    /// grey bar marks it, and it brightens while the pointer is on it or
    /// while you are dragging. Double-click puts the terminal back to its
    /// default height; the arrow keys move it once it has focus.
    private func sectionDivider(in height: CGFloat) -> some View {
        SplitHandle(
            dragging: dragShare != nil,
            onDrag: { translation, phase in
                guard height > 0 else { return }
                switch phase {
                case .changed:
                    let start = dragShare ?? terminalShare
                    dragShare = start
                    storedShare = Double(clampShare(start + translation / height))
                case .ended:
                    dragShare = nil
                }
            },
            onReset: {
                withAnimation(.easeInOut(duration: 0.18)) {
                    storedShare = Double(Self.defaultShare)
                }
            },
            onStep: { delta in
                guard height > 0 else { return }
                storedShare = Double(clampShare(terminalShare + delta / height))
            }
        )
    }

    /// The terminal keeps at least 120 points and leaves the boards at
    /// least 160, whatever the window is doing.
    private func clampShare(_ value: CGFloat) -> CGFloat {
        min(max(value, 0.18), 0.82)
    }

    static let defaultShare: CGFloat = 0.52

    private var terminalShare: CGFloat { clampShare(CGFloat(storedShare)) }

    // MARK: Sections

    /// The four faces, as a board strip: letter-spaced caps, a count beside
    /// the ones that have one, and a rule under the face you are on.
    private var sectionStrip: some View {
        HStack(spacing: 0) {
            ForEach(Array(FlightSection.allCases.enumerated()), id: \.element.id) { index, tab in
                SectionTab(
                    title: tab.rawValue,
                    count: sectionCount(tab),
                    active: ws.flightSection == tab,
                    first: index == 0
                ) {
                    withAnimation(.easeInOut(duration: 0.15)) { ws.flightSection = tab }
                }
            }
        }
        .background(Board.veilFloor)
    }

    /// What each face is holding, so you know before you open it.
    private func sectionCount(_ tab: FlightSection) -> Int? {
        switch tab {
        case .issue: return nil
        case .pulls:
            let count = flightPulls.count
            return count > 0 ? count : nil
        case .slides:
            let count = slideSets.reduce(0) { $0 + $1.slides.count }
            return count > 0 ? count : nil
        case .thread:
            let count = IssueBody.conversation("Situation Development", in: flight?.body ?? "").count
            return count > 0 ? count : nil
        }
    }

    /// The one box under the terminal: whatever face you are on, scrolling,
    /// with the four faces anchored along its floor. It takes the rest of
    /// the card whether the face has three rows or thirty, so the strip
    /// never floats up the pane behind a short board.
    @ViewBuilder
    private var sectionBody: some View {
        BoardBox {
            ScrollViewReader { scroll in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        // An anchor at the very top, so switching face starts
                        // you at the top of the new one rather than halfway
                        // down it. Outside the spaced stack, or its spacing
                        // becomes a gap above the first board.
                        Color.clear.frame(height: 0).id(Self.paneTop)
                        VStack(alignment: .leading, spacing: 14) {
                            switch ws.flightSection {
                            case .issue: issueSection
                            case .pulls: pullsSection
                            case .slides: slidesSection
                            case .thread: threadSection
                            }
                        }
                    }
                    .padding(.bottom, 18)
                }
                .contentMargins(.vertical, 0, for: .scrollContent)
                .scrollIndicators(.automatic)
                .onChange(of: ws.flightSection) {
                    scroll.scrollTo(Self.paneTop, anchor: .top)
                }
            }
            // What runs off the bottom fades into the floor rather than
            // being cut off at the strip's edge.
            .mask(
                LinearGradient(
                    stops: [
                        .init(color: .black, location: 0),
                        .init(color: .black, location: 0.93),
                        .init(color: .black.opacity(0), location: 1),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        } tabs: {
            sectionStrip
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 12)
    }

    private static let paneTop = "flight.pane.top"

    /// The legs as a departures board: a number, the stop, and where it
    /// stands. The first unfinished one is BOARDING and blinks; the rest are
    /// SCHEDULED; the ones behind it are LANDED. Remarks, which is what the
    /// issue says done looks like, sit at the foot of the same board.
    private var issueSection: some View {
        let steps = IssueBody.steps("Progress", in: flight?.body ?? "")
        let acceptance = IssueBody.steps("Acceptance", in: flight?.body ?? "")
        let boarding = steps.firstIndex { !$0.done }
        let cleared = acceptance.filter(\.done).count
        return BoardSheet {
            BoardColumns(names: ["No", "Stop", "Status"], widths: [34, nil, 92])

            if steps.isEmpty {
                boardNote("The pilot has not written a checklist for this flight yet.")
            } else {
                ForEach(Array(steps.enumerated()), id: \.element.id) { index, step in
                    BoardRow(index: index, ruled: index > 0, action: { copyStep(step) }) {
                        stepRow(step, number: index + 1, boarding: index == boarding)
                    }
                    .contextMenu {
                        Button("Copy step") { copyStep(step) }
                        if step.needs != nil {
                            Button("Copy what it waits on") {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(step.needs ?? "", forType: .string)
                            }
                        }
                    }
                    .help("Copy this step")
                }
            }

            // Remarks is part of the same board, under a rule, the way a
            // flight sheet carries its notes under the stops.
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("REMARKS")
                        .font(.mono(7))
                        .tracking(1.8)
                        .foregroundStyle(Board.faint)
                    Spacer(minLength: 8)
                    if !acceptance.isEmpty {
                        Text(verbatim: "\(cleared)/\(acceptance.count)")
                            .font(.mono(7))
                            .tracking(1.4)
                            .foregroundStyle(Board.faint)
                    }
                }
                .padding(.bottom, 2)

                if acceptance.isEmpty {
                    Text("This issue says nothing about what done looks like.")
                        .font(.mono(9.5))
                        .foregroundStyle(Board.dim)
                        .padding(.vertical, 8)
                        .fixedSize(horizontal: false, vertical: true)
                }

                ForEach(Array(acceptance.enumerated()), id: \.element.id) { index, line in
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(line.done ? Board.purple : Color.clear)
                            .overlay(
                                RoundedRectangle(cornerRadius: 2)
                                    .strokeBorder(line.done ? Board.purple : Board.faint, lineWidth: 1.5)
                            )
                            .frame(width: 11, height: 11)
                            .offset(y: 1)
                        MarkdownText(text: line.text.uppercased())
                            .font(.mono(9.5))
                            .foregroundStyle(line.done ? Board.muted : Board.text)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 10)
                        Text(line.done ? "CLEARED" : "PENDING")
                            .font(.mono(7.5))
                            .tracking(1.4)
                            .foregroundStyle(line.done ? Board.purple : Board.faint)
                            .fixedSize()
                    }
                    .padding(.vertical, 8)
                    .overlay(alignment: .top) {
                        if index > 0 { Rectangle().fill(Board.row).frame(height: 1) }
                    }
                }
            }
            .padding(.horizontal, Board.gutter)
            .padding(.top, 9)
            .padding(.bottom, 6)
            .overlay(alignment: .top) { Rectangle().fill(Board.rule).frame(height: 1) }
        }
    }

    /// One stop on the board.
    private func stepRow(_ step: IssueBody.Step, number: Int, boarding: Bool) -> some View {
        let word = step.done ? "LANDED" : (boarding ? "BOARDING" : "SCHEDULED")
        let ink = step.done ? Board.purple : (boarding ? Board.teal : Board.faint)
        return HStack(alignment: .top, spacing: 10) {
            Text(String(format: "%02d", number))
                .font(.mono(9))
                .foregroundStyle(Board.dim)
                .frame(width: 34, alignment: .leading)

            VStack(alignment: .leading, spacing: 3) {
                MarkdownText(text: step.label.uppercased())
                    .font(.mono(10.5))
                    .foregroundStyle(step.done ? Board.muted : Board.ink)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                if let needs = step.needs, !step.done {
                    MarkdownText(text: needs, tint: Board.amber)
                        .font(.mono(8.5))
                        .foregroundStyle(Board.amber.opacity(0.9))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(word)
                .font(.mono(8))
                .tracking(1.4)
                .foregroundStyle(ink)
                .frame(width: 92, alignment: .trailing)
                .opacity(boarding && blink ? 0.4 : 1)
        }
    }

    /// A line of plain words where a board would otherwise be empty.
    private func boardNote(_ text: String) -> some View {
        Text(text)
            .font(.mono(9.5))
            .foregroundStyle(Board.dim)
            .padding(.horizontal, Board.gutter)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
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

    /// Every PR of the flight, in three boards: draft, open, then closed.
    /// Each row is its number, its title on one line, the branch under it,
    /// and where it stands at the end. A bracket tag in the title, like
    /// [MERGE AFTER WEEKEND], is pulled out of the sentence and shown in
    /// amber, because it is an instruction and not part of the name.
    private var pullsSection: some View {
        let all = flightPulls
        let groups = Self.grouped(all)
        return BoardSheet {
            if all.isEmpty {
                BoardBar("Pull requests")
                boardNote("No pull request names this flight or its crews yet.")
            }
            // One continuous board, not one board a group. A group is a bar
            // across the rows, the way a day is a bar across the log: with a
            // gap between them the last row of a group grew a floor of empty
            // sheet under it and read as a taller row than the rest.
            ForEach(Array(groups.enumerated()), id: \.element.id) { groupIndex, group in
                BoardBar(title: group.name, dot: group.colour) {
                    BoardTally(
                        text: group.capped
                            ? "Showing \(min(pullsShown, group.pulls.count)) of \(group.pulls.count)"
                            : "\(group.pulls.count)"
                    )
                }
                .overlay(alignment: .top) {
                    if groupIndex > 0 { Rectangle().fill(Board.row).frame(height: 1) }
                }
                BoardColumns(names: ["No", "Pull", "Status"], widths: [52, nil, 62])
                let shown = group.capped ? Array(group.pulls.prefix(pullsShown)) : group.pulls
                ForEach(Array(shown.enumerated()), id: \.element.id) { index, pull in
                    BoardRow(index: index, ruled: index > 0, action: {
                        NSWorkspace.shared.open(pull.url)
                    }) {
                        pullRow(pull)
                    }
                }
                if shown.count < group.pulls.count {
                    BoardMore(title: "Load \(group.pulls.count - shown.count) more") {
                        pullsShown += 20
                    }
                }
            }
        }
    }

    /// Draft, then open, then everything that is finished with.
    ///
    /// Reading one long list of pulls meant hunting for the three that still
    /// want something from you among thirty that merged weeks ago. The order
    /// is the order you act in. Only the closed pile is capped, because it
    /// is the only one that grows without end.
    private struct PullGroup: Identifiable {
        let name: String
        let colour: Color
        let pulls: [RepositoryPullRequest]
        let capped: Bool
        var id: String { name }
    }

    private static func grouped(_ all: [RepositoryPullRequest]) -> [PullGroup] {
        let draft = all.filter { $0.isOpen && $0.isDraft }
        let open = all.filter { $0.isOpen && !$0.isDraft }
        let closed = all.filter { !$0.isOpen }
        return [
            PullGroup(name: "Draft", colour: Board.amber, pulls: draft, capped: false),
            PullGroup(name: "Open", colour: Board.teal, pulls: open, capped: false),
            PullGroup(name: "Closed", colour: Board.purple, pulls: closed, capped: true),
        ].filter { !$0.pulls.isEmpty }
    }

    private func pullRow(_ pull: RepositoryPullRequest) -> some View {
        let parsed = Self.tagged(pull.title)
        return HStack(alignment: .top, spacing: 10) {
            // Verbatim: an interpolated Int is a localized number, and the
            // pane printed #17.416 for pull 17416.
            // The number wears the pull's own state, the same colour as the
            // word at the other end of the row, so a row reads from either
            // side. Purple for everything was a merged board's colour worn
            // by an open PR.
            Text(verbatim: "#\(pull.number)")
                .font(.mono(9))
                .foregroundStyle(stateColour(pull))
                .frame(width: 52, alignment: .leading)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    if let tag = parsed.tag {
                        Text(tag)
                            .font(.mono(8.5))
                            .tracking(0.8)
                            .foregroundStyle(Board.amber)
                            .fixedSize()
                    }
                    Text(parsed.title)
                        .font(.mono(10))
                        .foregroundStyle(Board.ink)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                Text(verbatim: "\(pull.headRefName) → \(pull.baseRefName)")
                    .font(.mono(8.5))
                    .foregroundStyle(Board.faint)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .trailing, spacing: 2) {
                Text(stateLabel(pull))
                    .font(.mono(7.5, .medium))
                    .tracking(1.4)
                    .foregroundStyle(stateColour(pull))
                Text(Self.shortDay.string(from: pull.timeframeDate))
                    .font(.mono(8))
                    .foregroundStyle(Board.dim)
            }
            .frame(width: 62, alignment: .trailing)
        }
        .help(pull.title)
    }

    /// A leading `[LIKE THIS]` is an instruction, not part of the name.
    static func tagged(_ title: String) -> (tag: String?, title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("["), let close = trimmed.firstIndex(of: "]") else {
            return (nil, trimmed)
        }
        let tag = String(trimmed[trimmed.index(after: trimmed.startIndex)..<close])
        let rest = trimmed[trimmed.index(after: close)...].trimmingCharacters(in: .whitespaces)
        return (tag.uppercased(), rest.isEmpty ? trimmed : rest)
    }

    static let shortDay: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "d MMM"
        return formatter
    }()

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

    /// One board per walkthrough: its name and issue in the bar, a button to
    /// its folder, and the real slides underneath.
    private var slidesSection: some View {
        let sets = slideSets
        return VStack(alignment: .leading, spacing: 12) {
            if sets.isEmpty {
                BoardSheet {
                    BoardBar("Walkthrough")
                    boardNote("No walkthrough slides for this flight or its crews yet.")
                }
            }

            ForEach(sets) { set in
                BoardSheet {
                    HStack(spacing: 8) {
                        Text(set.title.uppercased())
                            .font(.mono(7.5, .semibold))
                            .tracking(1.6)
                            .foregroundStyle(Board.ink)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Text(verbatim: GitHubNumber.reference(set.issue))
                            .font(.mono(7.5))
                            .tracking(1)
                            .foregroundStyle(Board.teal)
                            .fixedSize()
                            .onTapGesture {
                                if let flight, set.issue == flight.number {
                                    NSWorkspace.shared.open(flight.url)
                                } else if let crew = flight?.legs.first(where: { $0.number == set.issue }) {
                                    NSWorkspace.shared.open(crew.url)
                                }
                            }
                            .pointerCursor()
                        Spacer(minLength: 8)
                        BoardAction(title: "Open folder") {
                            NSWorkspace.shared.open(set.slides[0].deletingLastPathComponent())
                        }
                    }
                    .padding(.horizontal, Board.gutter)
                    .padding(.vertical, 7)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Board.veilBar)

                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 118), spacing: 10)],
                        spacing: 10
                    ) {
                        ForEach(set.slides, id: \.self) { slide in
                            VStack(alignment: .leading, spacing: 5) {
                                slideThumbnail(slide)
                                Text(slide.deletingPathExtension().lastPathComponent)
                                    .font(.mono(8))
                                    .foregroundStyle(Board.dim)
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                            }
                            .contentShape(Rectangle())
                            .onTapGesture { NSWorkspace.shared.open(slide) }
                            .pointerCursor()
                            .help(slide.lastPathComponent)
                        }
                    }
                    .padding(.horizontal, Board.gutter)
                    .padding(.vertical, 12)
                }
            }
        }
    }

    private func slideThumbnail(_ slide: URL) -> some View {
        SlideThumbnail(slide: slide)
    }

    /// Two boards: where this flight is talked about, and the log of what
    /// was said. The log reads as a sheet, a sticky day bar over each day's
    /// entries and the speaker in a column of its own.
    private var threadSection: some View {
        let entries = IssueBody.conversation("Situation Development", in: flight?.body ?? "")
        let home = IssueBody.homeThread("Situation Development", in: flight?.body ?? "")
        let channels = IssueBody.channels("Situation Development", in: flight?.body ?? "")
        return VStack(alignment: .leading, spacing: 12) {
            if !channels.isEmpty {
                BoardSheet {
                    BoardBar(title: "Channels") {
                        BoardTally(text: "\(channels.count)")
                    }
                    FlowRow(spacing: 6) {
                        ForEach(channels) { channel in
                            channelChip(channel, fallback: home)
                        }
                    }
                    .padding(.horizontal, Board.gutter)
                    .padding(.vertical, 10)
                }
            }

            BoardSheet {
                BoardBar(title: "Situation") {
                    BoardTally(text: entries.isEmpty ? "" : "\(entries.count)")
                }

                if entries.isEmpty {
                    boardNote("This issue keeps no conversation log yet.")
                }

                ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                    if let day = entry.day, day != entries[safe: index - 1]?.day {
                        Text(day.uppercased())
                            .font(.mono(7.5))
                            .tracking(1.8)
                            .foregroundStyle(Board.dim)
                            .padding(.horizontal, Board.gutter)
                            .padding(.vertical, 6)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Board.veilDay)
                            .overlay(alignment: .top) { Rectangle().fill(Board.row).frame(height: 1) }
                            .overlay(alignment: .bottom) { Rectangle().fill(Board.row).frame(height: 1) }
                    }

                    HStack(alignment: .top, spacing: 10) {
                        Text(entry.who.uppercased())
                            .font(.mono(8))
                            .tracking(1.2)
                            .foregroundStyle(whoInk(entry.who))
                            .frame(width: 58, alignment: .leading)
                            .lineLimit(2)
                            .truncationMode(.tail)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                if let link = entry.link { NSWorkspace.shared.open(link) }
                            }
                            .pointerCursor()
                        MarkdownText(text: entry.said, tint: Board.teal)
                            .font(.mono(9.5))
                            .foregroundStyle(Board.text)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.horizontal, Board.gutter)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    /// Who said it: the bots in amber, Erbin in teal, everyone else grey.
    private func whoInk(_ who: String) -> Color {
        let name = who.lowercased()
        if name.contains("sentry") || name.contains("bot") || name.contains("github") {
            return Board.amber
        }
        if name.contains("erbin") { return Board.teal }
        return Board.muted
    }

    /// One channel, as a chip that opens it.
    private func channelChip(_ channel: IssueBody.Channel, fallback: URL?) -> some View {
        ChannelChip(name: channel.name) {
            if let link = channel.link ?? fallback { NSWorkspace.shared.open(link) }
        }
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


/// One square in the walkthrough grid.
///
/// It owns its own image, so a slide finishing its decode redraws this
/// square and nothing else. Reading a shared store from the pane's body
/// instead meant every arrival redrew every slide on the tab.
private struct SlideThumbnail: View {
    let slide: URL
    @State private var image: NSImage?
    @State private var shimmer = false

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                // A shimmer rather than a placeholder glyph: a grid of empty
                // frames reads as broken, a moving one reads as loading.
                LinearGradient(
                    colors: [Board.hover, Color(red: 0.106, green: 0.110, blue: 0.122), Board.hover],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .opacity(shimmer ? 1 : 0.55)
                .animation(
                    .easeInOut(duration: 0.7).repeatForever(autoreverses: true),
                    value: shimmer
                )
                .onAppear { shimmer = true }
            }
        }
        .aspectRatio(16.0 / 11.0, contentMode: .fit)
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Board.rule, lineWidth: 1)
        )
        .task(id: slide) {
            image = await SlideThumbnails.shared.thumbnail(for: slide)
        }
    }
}
