import SwiftUI

/// The pilot's pane: the agent flying one flight on top, and everything that
/// flight is made of underneath.
///
/// Nothing here is wired to real data yet. The sample below is placeholder, so
/// the shape can be judged before a flight model exists.
struct MiddlePane: View {
    @State private var crewTab: PilotSeat = .pilot
    @State private var section: FlightSection = .issue
    /// How much of the pane the terminal takes, as a fraction.
    @State private var terminalShare: CGFloat = 0.52
    @State private var dragStartShare: CGFloat?
    @State private var draft = FlightPreview.sampleDraft
    /// The flight's own issue: open while it flies, closed once it lands.
    @State private var flightClosed = false

    private let flight = FlightPreview.sample

    var body: some View {
        GeometryReader { geo in
            let terminalHeight = max(140, min(geo.size.height - 180, geo.size.height * terminalShare))

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
        .background(Color(white: 0.035))
    }

    // MARK: Header

    private var flightHeader: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 7) {
                Text("FLIGHT")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.3))
                    .tracking(0.8)
                Text(verbatim: GitHubNumber.reference(flight.number))
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Runway.teal.opacity(0.9))
                Spacer(minLength: 8)
                statusChip(flight.status)
            }

            Text(flight.title)
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
        let flown = flight.legs.filter(\.done).count
        return HStack(spacing: 4) {
            Circle()
                .fill(Runway.green.opacity(0.9))
                .frame(width: 5, height: 5)

            ForEach(Array(flight.legs.enumerated()), id: \.element.id) { index, leg in
                if index == flown, flown < flight.legs.count {
                    Image(systemName: "airplane")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Runway.teal)
                }
                legSegment(done: leg.done)
            }

            if flown == flight.legs.count {
                Image(systemName: "airplane.arrival")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Runway.green)
            }

            Circle()
                .strokeBorder(Color.white.opacity(0.28), lineWidth: 1)
                .frame(width: 5, height: 5)

            Text("\(flown)/\(flight.legs.count) legs")
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
                            .fill(seat == .pilot ? Runway.green : Color.white.opacity(0.22))
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

    private var terminalArea: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 9)
                .fill(Color(white: 0.055))
            RoundedRectangle(cornerRadius: 9)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
            VStack(spacing: 6) {
                Image(systemName: "dot.radiowaves.left.and.right")
                    .font(.system(size: 15))
                    .foregroundStyle(Color.white.opacity(0.18))
                Text("\(crewTab.rawValue) terminal")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.3))
            }
        }
        .padding(.horizontal, 12)
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
            // The legs read as a strip you scroll along, in the order they fly.
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(flight.legs) { leg in
                        legCard(leg)
                    }
                }
                .padding(.vertical, 1)
            }
            .scrollIndicators(.hidden)
            .contentMargins(.horizontal, 0, for: .scrollContent)

            sectionLabel("ACCEPTANCE")
            VStack(alignment: .leading, spacing: 5) {
                ForEach(flight.acceptance, id: \.self) { line in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Image(systemName: "square")
                            .font(.system(size: 9))
                            .foregroundStyle(Color.white.opacity(0.22))
                        Text(line)
                            .font(.system(size: 12))
                            .foregroundStyle(Color.white.opacity(0.72))
                    }
                }
            }

            stateButton
                .padding(.top, 4)
        }
    }

    private func legCard(_ leg: FlightPreview.Leg) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: leg.done ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 10))
                    .foregroundStyle(leg.done ? Runway.green : Color.white.opacity(0.25))
                Text(verbatim: GitHubNumber.reference(leg.number))
                    .font(.system(size: 9.5, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.32))
                Spacer(minLength: 0)
            }

            Text(leg.title)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(Color.white.opacity(leg.done ? 0.45 : 0.85))
                .strikethrough(leg.done, color: Color.white.opacity(0.3))
                .multilineTextAlignment(.leading)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let blocker = leg.blocker {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    if leg.needsYou {
                        Circle()
                            .fill(Runway.amber)
                            .frame(width: 4, height: 4)
                    }
                    Text(blocker)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(
                            leg.needsYou ? Runway.amber : Color.white.opacity(0.38)
                        )
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
            }
        }
        .padding(9)
        .frame(width: 150, alignment: .topLeading)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.04)))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.white.opacity(leg.done ? 0.06 : 0.11), lineWidth: 1)
        )
    }

    /// Close the flight's issue once it has landed, or put it back in the air.
    private var stateButton: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) { flightClosed.toggle() }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: flightClosed ? "arrow.counterclockwise.circle" : "checkmark.circle")
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
            ForEach(flight.pulls) { pull in
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 7) {
                        Text(verbatim: GitHubNumber.reference(pull.number))
                            .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                            .foregroundStyle(Runway.green.opacity(0.82))
                        Text(pull.title)
                            .font(.system(size: 11))
                            .foregroundStyle(Color.white.opacity(0.75))
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        checkChip(pull.checks)
                    }
                    HStack(spacing: 5) {
                        Text(pull.branch)
                        Image(systemName: "arrow.right")
                            .font(.system(size: 7, weight: .semibold))
                        Text("main")
                    }
                    .font(.system(size: 8.5, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.27))
                    .lineLimit(1)
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 7).fill(Color.white.opacity(0.03)))
            }
        }
    }

    private func checkChip(_ state: CheckState) -> some View {
        Text(state.label)
            .font(.system(size: 8, weight: .bold, design: .monospaced))
            .foregroundStyle(state.color)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(Capsule().fill(state.color.opacity(0.12)))
    }

    /// The evidence this flight has produced.
    private var slidesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("WALKTHROUGH")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 8)], spacing: 8) {
                ForEach(flight.slides, id: \.self) { slide in
                    VStack(alignment: .leading, spacing: 5) {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color(white: 0.08))
                            .aspectRatio(1, contentMode: .fit)
                            .overlay(
                                Image(systemName: "photo")
                                    .font(.system(size: 14))
                                    .foregroundStyle(Color.white.opacity(0.16))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(Color.white.opacity(0.07), lineWidth: 1)
                            )
                        Text(slide)
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(Color.white.opacity(0.4))
                            .lineLimit(1)
                    }
                }
            }
        }
    }

    /// The conversation this flight lives in, newest last, each line linking
    /// back out to where it was said.
    private var threadSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                sectionLabel("SITUATION")
                Spacer(minLength: 8)
                Button {
                    // The flight's home thread, wherever the talking happens.
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
                .help("Open this flight's thread in Slack")
            }

            ForEach(flight.thread) { entry in
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
                        HStack(spacing: 6) {
                            Text(entry.who)
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(Runway.teal.opacity(0.85))
                            Text(entry.when)
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundStyle(Color.white.opacity(0.26))
                        }
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

// MARK: Placeholder

/// Stand-in content, so the pane can be judged before flights are real.
struct FlightPreview {
    struct Leg: Identifiable {
        let number: Int
        let title: String
        let done: Bool
        /// What this leg is held up by, if anything.
        var blocker: String?
        /// True when the one holding it up is you.
        var needsYou = false
        var id: Int { number }
    }

    struct Pull: Identifiable {
        let number: Int
        let title: String
        let branch: String
        let checks: CheckState
        var id: Int { number }
    }

    struct ThreadEntry: Identifiable {
        let who: String
        let when: String
        let said: String
        var id: String { who + when }
    }

    let number: Int
    let title: String
    let status: String
    let legs: [Leg]
    let acceptance: [String]
    let pulls: [Pull]
    let slides: [String]
    let thread: [ThreadEntry]

    /// A pilot's unsent message, in Erbin's voice.
    static let sampleDraft = """
    the POS booking form is in and holding a slot works. refunds wait on your     answer about the Teya path, want me to mirror the existing refund flow or     wait for the new one?
    """

    static let sample = FlightPreview(
        number: 16200,
        title: "Bookings: take a booking on the POS",
        status: "holding",
        legs: [
            Leg(number: 16257, title: "Booking form on the POS", done: true,
                blocker: "close it? acceptance met", needsYou: true),
            Leg(number: 16261, title: "Hold a slot while paying", done: true,
                blocker: "merge #16290? lunch lock on", needsYou: true),
            Leg(number: 16264, title: "Refund a cancelled booking", done: false,
                blocker: "waits on a reply from Arnar"),
            Leg(number: 16270, title: "Receipt shows the slot", done: false),
        ],
        acceptance: [
            "A booking taken on the POS appears in the dashboard within a minute.",
            "A cancelled booking refunds in full, once.",
            "The printed receipt names the slot and the staff member.",
        ],
        pulls: [
            Pull(number: 16290, title: "feat(upsell-pos): booking form",
                 branch: "feat/pos-booking-form-16257", checks: .passing),
            Pull(number: 16294, title: "feat(bookings-api): hold a slot",
                 branch: "feat/hold-slot-16261", checks: .running),
        ],
        slides: ["booking taken", "slot held", "refund"],
        thread: [
            ThreadEntry(who: "Erbin", when: "Tue 09:12",
                        said: "Brauð wants bookings on the POS before 2 Jan."),
            ThreadEntry(who: "Arnar", when: "Tue 14:40",
                        said: "Refunds go through the same Teya path, I'll confirm the flow."),
            ThreadEntry(who: "pilot", when: "Wed 08:05",
                        said: "Two legs landed; the refund leg waits on Arnar's answer."),
        ]
    )
}
