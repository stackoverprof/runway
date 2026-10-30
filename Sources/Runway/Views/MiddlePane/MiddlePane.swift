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
    @State private var crewTab: PilotSeat = .pilot
    @State private var section: FlightSection = .issue
    /// How much of the pane the terminal takes, as a fraction.
    @State private var terminalShare: CGFloat = 0.52
    @State private var dragStartShare: CGFloat?
    @State private var draft = ""

    /// The issue being flown, if one is picked and still ours.
    private var flight: AssignedIssue? { issues.issue(ws.flightNumber) }

    var body: some View {
        GeometryReader { geo in
            let terminalHeight = max(140, min(geo.size.height - 180, geo.size.height * terminalShare))

            if flight == nil {
                nothingFlying
            } else {
            VStack(spacing: 0) {
                flightHeader
                seatStrip
                terminalArea
                    .frame(height: terminalHeight)
                sectionDivider(in: geo.size.height)
                sectionStrip
                sectionBody
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            }
        }
        .background(Color(white: 0.035))
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
                statusChip(flight?.isClosed == true ? "landed" : "in the air")
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
    }

    /// The flight as a route: the legs behind it flown in green, the aircraft
    /// where it is now, the legs ahead in grey.
    private var legsBar: some View {
        let legs = flight?.legs ?? []
        let flown = legs.filter(\.isClosed).count
        return HStack(spacing: 4) {
            Circle()
                .fill(Runway.green.opacity(0.9))
                .frame(width: 5, height: 5)

            ForEach(Array(legs.enumerated()), id: \.element.id) { index, leg in
                if index == flown, flown < legs.count {
                    Image(systemName: "airplane")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Runway.teal)
                }
                legSegment(done: leg.isClosed)
            }

            if legs.isEmpty {
                Capsule()
                    .fill(Color.white.opacity(0.14))
                    .frame(height: 3)
            }

            if !legs.isEmpty, flown == legs.count {
                Image(systemName: "airplane.arrival")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Runway.green)
            }

            Circle()
                .strokeBorder(Color.white.opacity(0.28), lineWidth: 1)
                .frame(width: 5, height: 5)

            Text(legs.isEmpty ? "no crews yet" : "\(flown)/\(legs.count) crews")
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(Color.white.opacity(0.32))
                .fixedSize()
                .padding(.leading, 2)
        }
    }

    private func legSegment(done: Bool) -> some View {
        Capsule()
            .fill(done ? Runway.green : Color.white.opacity(0.14))
            .frame(height: 3)
    }

    private func statusChip(_ status: String) -> some View {
        Text(status.uppercased())
            .font(.system(size: 8.5, weight: .bold, design: .monospaced))
            .foregroundStyle(Runway.amber)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Capsule().fill(Runway.amber.opacity(0.12)))
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
            Spacer(minLength: 8)
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
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

    private var terminalArea: some View {
        Group {
        if let flight, let repository = issues.repository {
            // Both seats stay mounted, so switching back finds the
            // conversation where you left it rather than starting one.
            ZStack {
                ForEach(PilotSeat.allCases) { seat in
                    seatTerminal(seat, flight: flight, repository: repository)
                        .opacity(crewTab == seat ? 1 : 0)
                        .allowsHitTesting(crewTab == seat)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 9))
            .overlay(
                RoundedRectangle(cornerRadius: 9)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
            .padding(.horizontal, 12)
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 9)
                    .fill(Color(white: 0.055))
                RoundedRectangle(cornerRadius: 9)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            }
            .padding(.horizontal, 12)
        }
        }
    }

    private func seatTerminal(
        _ seat: PilotSeat,
        flight: AssignedIssue,
        repository: String
    ) -> some View {
        let rank: AgentRank = seat == .pilot ? .pilot : .copilot
        return TerminalSurfaceView(
            boxID: FlightCrewSessions.boxID(
                rank: rank,
                repository: repository,
                issue: flight.number
            ),
            workspace: ws,
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
        ZStack {
            Rectangle()
                .fill(Color.white.opacity(0.07))
                .frame(height: 1)
        }
        .frame(height: 14)
        .contentShape(Rectangle())
        .onHover { hovering in
            if hovering { NSCursor.resizeUpDown.set() } else { NSCursor.arrow.set() }
        }
        .gesture(
            DragGesture()
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
    }

    /// The legs, what each waits on, and what only you can answer.
    private var issueSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionLabel("PROGRESS")
            // The pilot's own checklist, kept in the issue body. The crews are
            // the route above and the pane to the right; this is the steps.
            let steps = IssueBody.steps("Progress", in: flight?.body ?? "")
            VStack(alignment: .leading, spacing: 6) {
                if steps.isEmpty {
                    Text("The pilot has not written a checklist for this flight yet.")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Color.white.opacity(0.3))
                }
                ForEach(Array(steps.enumerated()), id: \.element.id) { index, step in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Image(systemName: step.done ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 10))
                            .foregroundStyle(step.done ? Runway.green : Color.white.opacity(0.25))
                        Text(step.text)
                            .font(.system(size: 12))
                            .foregroundStyle(Color.white.opacity(step.done ? 0.42 : 0.85))
                            .strikethrough(step.done, color: Color.white.opacity(0.3))
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 6)
                        Text("\(index + 1)")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(Color.white.opacity(0.22))
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
                        Text(line.text)
                            .font(.system(size: 12))
                            .foregroundStyle(Color.white.opacity(line.done ? 0.45 : 0.72))
                    }
                }
            }

            stateButton(closed: flight?.isClosed == true)
                .padding(.top, 4)
        }
    }

    /// Close the flight's issue once it has landed, or put it back in the air.
    private func stateButton(closed flightClosed: Bool) -> some View {
        Button {
            guard let number = flight?.number, !closing else { return }
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
            .foregroundStyle(flightClosed ? Runway.green : Runway.purple)
            .frame(maxWidth: .infinity)
            .frame(height: 28)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill((flightClosed ? Runway.green : Runway.purple).opacity(0.1))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .stroke((flightClosed ? Runway.green : Runway.purple).opacity(0.28), lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .pointerCursor()
    }

    /// Every PR of the flight, with what it is waiting for.
    private var pullsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("PULL REQUESTS")
            if flightPulls.isEmpty {
                Text("No pull request names this flight or its crews yet.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Color.white.opacity(0.3))
            }
            ForEach(flightPulls) { pull in
                Button {
                    NSWorkspace.shared.open(pull.url)
                } label: {
                    VStack(alignment: .leading, spacing: 5) {
                        HStack(spacing: 7) {
                            Text(verbatim: GitHubNumber.reference(pull.number))
                                .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                                .foregroundStyle(stateColour(pull).opacity(0.85))
                            Text(pull.title)
                                .font(.system(size: 11))
                                .foregroundStyle(Color.white.opacity(0.75))
                                .lineLimit(1)
                            Spacer(minLength: 4)
                            Text(stateLabel(pull))
                                .font(.system(size: 8, weight: .bold, design: .monospaced))
                                .foregroundStyle(stateColour(pull))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(stateColour(pull).opacity(0.12)))
                        }
                        HStack(spacing: 5) {
                            Text(pull.headRefName)
                            Image(systemName: "arrow.right")
                                .font(.system(size: 7, weight: .semibold))
                            Text(pull.baseRefName)
                        }
                        .font(.system(size: 8.5, design: .monospaced))
                        .foregroundStyle(Color.white.opacity(0.27))
                        .lineLimit(1)
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 7).fill(Color.white.opacity(0.03)))
                    .contentShape(RoundedRectangle(cornerRadius: 7))
                }
                .buttonStyle(.plain)
                .pointerCursor()
            }
        }
    }

    /// Every PR whose branch ends in this flight's number or one of its
    /// crews', which is what the branch convention makes possible.
    private var flightPulls: [RepositoryPullRequest] {
        guard let flight else { return [] }
        let numbers = Set([flight.number] + flight.legs.map(\.number))
        return pullRequests.pullRequests
            .filter { pull in
                BranchIssue.number(in: pull.headRefName).map(numbers.contains) ?? false
            }
            .sorted { $0.number > $1.number }
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
    private var slidesSection: some View {
        let slides = WalkthroughSlides.forIssue(flight?.number)
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                sectionLabel("WALKTHROUGH")
                Spacer(minLength: 8)
                if !slides.isEmpty {
                    Button {
                        NSWorkspace.shared.open(slides[0].deletingLastPathComponent())
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
            }

            if slides.isEmpty {
                Text("No walkthrough slides for this flight yet.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Color.white.opacity(0.3))
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 8)], spacing: 8) {
                ForEach(slides, id: \.self) { slide in
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

    private func slideThumbnail(_ slide: URL) -> some View {
        Group {
            if let image = NSImage(contentsOf: slide) {
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
                            Text("Open thread")
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

            ForEach(entries) { entry in
                HStack(alignment: .top, spacing: 9) {
                    VStack(spacing: 0) {
                        Circle()
                            .fill(Color.white.opacity(0.28))
                            .frame(width: 5, height: 5)
                        Rectangle()
                            .fill(Color.white.opacity(0.08))
                            .frame(width: 1)
                            .frame(maxHeight: .infinity)
                    }
                    .padding(.top, 5)

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
                        Text(entry.said)
                            .font(.system(size: 11.5))
                            .foregroundStyle(Color.white.opacity(0.78))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.bottom, 8)
                }
            }

            draftComposer
        }
    }

    /// What a pilot drafted, in your voice, waiting for you to send or bin it.
    private var draftComposer: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                sectionLabel("DRAFT")
                Circle()
                    .fill(Runway.amber)
                    .frame(width: 4, height: 4)
                Text("unsent")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(Runway.amber.opacity(0.8))
            }

            TextEditor(text: $draft)
                .font(.system(size: 11.5))
                .scrollContentBackground(.hidden)
                .padding(8)
                .frame(minHeight: 72)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.04)))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.white.opacity(0.09), lineWidth: 1)
                )
                .overlay(alignment: .topLeading) {
                    if draft.isEmpty {
                        Text("Nothing drafted for this flight yet.")
                            .font(.system(size: 11.5))
                            .foregroundStyle(Color.white.opacity(0.25))
                            .padding(.horizontal, 13)
                            .padding(.vertical, 16)
                            .allowsHitTesting(false)
                    }
                }

            HStack(spacing: 8) {
                Button {
                    draft = ""
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 10.5))
                        .foregroundStyle(Color.white.opacity(0.45))
                        .frame(width: 26, height: 22)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.05)))
                        .contentShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .pointerCursor()
                .help("Bin this draft")
                .disabled(draft.isEmpty)

                Spacer(minLength: 0)

                Button {
                    // Sending is yours; the pilot only ever drafts.
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "paperplane.fill")
                            .font(.system(size: 9.5))
                        Text("Send")
                            .font(.system(size: 10.5, weight: .semibold))
                    }
                    .foregroundStyle(draft.isEmpty ? Color.white.opacity(0.3) : Color.black.opacity(0.85))
                    .padding(.horizontal, 12)
                    .frame(height: 22)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(draft.isEmpty ? Color.white.opacity(0.05) : Runway.teal)
                    )
                    .contentShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .pointerCursor()
                .disabled(draft.isEmpty)
            }
        }
        .padding(.top, 4)
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
    case pulls = "PRs"
    case slides = "Slides"
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
