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
    @State private var crews = CrewPreview.sample
    @State private var reading: Int?

    var body: some View {
        GeometryReader { geo in
            let active = crews.filter(\.isActive)
            let standing = crews.filter { !$0.isActive }
            let spans = CrewSpanPolicy.spans(
                active: active.map(\.issueNumber),
                reading: reading,
                paneHeight: geo.size.height,
                standingCount: standing.count
            )

            // An accordion, never a scroller: every crew is on screen at once,
            // the ones that are up sharing whatever the cards leave behind.
            VStack(spacing: CrewSpanPolicy.gap) {
                ForEach($crews) { $crew in
                    if crew.isActive {
                        activeBox($crew, height: spans[crew.issueNumber] ?? CrewSpanPolicy.minimumBox)
                    } else {
                        standingCard($crew)
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .clipped()
        }
        .background(Color.black)
    }

    // MARK: Stood down

    /// Nothing running, nothing on screen but the issue it answers for.
    private func standingCard(_ crew: Binding<CrewPreview>) -> some View {
        HStack(spacing: 10) {
            Circle()
                .strokeBorder(Color.white.opacity(0.3), lineWidth: 1.2)
                .frame(width: 11, height: 11)

            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: "\(crew.wrappedValue.repository) \(GitHubNumber.reference(crew.wrappedValue.issueNumber))")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.white.opacity(0.42))
                Text(crew.wrappedValue.title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.72))
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            activateButton(crew, active: false)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 9).fill(Color(white: 0.055)))
        .overlay(
            RoundedRectangle(cornerRadius: 9)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 9))
        .onTapGesture { activate(crew) }
        .pointerCursor()
    }

    // MARK: Flying

    private func activeBox(_ crew: Binding<CrewPreview>, height: CGFloat) -> some View {
        let value = crew.wrappedValue
        let isReading = reading == value.issueNumber
        return VStack(spacing: 0) {
            HStack(spacing: 8) {
                Circle()
                    .fill(value.state.color)
                    .frame(width: 7, height: 7)
                    .shadow(color: value.state.color.opacity(0.7), radius: 4)

                Text(value.title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.9))
                    .lineLimit(1)

                Spacer(minLength: 8)

                Text(value.branch)
                    .font(.system(size: 8.5, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.26))
                    .lineLimit(1)

                Text(verbatim: GitHubNumber.reference(value.issueNumber))
                    .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.4))

                activateButton(crew, active: true)
            }
            .padding(.horizontal, 11)
            .frame(height: 28)
            .background(RunwayTerminal.headerBar)

            ZStack {
                Color(white: 0.045)
                VStack(spacing: 5) {
                    Image(systemName: "terminal")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.white.opacity(0.16))
                    Text("\(value.repository)-\(value.issueNumber)")
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(Color.white.opacity(0.3))
                }
            }
        }
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: 9))
        .overlay(
            RoundedRectangle(cornerRadius: 9)
                .stroke(
                    isReading ? Runway.teal.opacity(0.45) : Color.white.opacity(0.1),
                    lineWidth: 1
                )
        )
        .contentShape(RoundedRectangle(cornerRadius: 9))
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.2)) { reading = value.issueNumber }
        }
    }

    /// The one control that matters on a card: bring this crew up, or stand it
    /// down and give the pane back.
    private func activateButton(_ crew: Binding<CrewPreview>, active: Bool) -> some View {
        Button {
            if active { standDown(crew) } else { activate(crew) }
        } label: {
            Image(systemName: active ? "stop.fill" : "play.fill")
                .font(.system(size: 8.5))
                .foregroundStyle(active ? Color.white.opacity(0.45) : Runway.green)
                .frame(width: 20, height: 20)
                .background(
                    Circle().fill(active ? Color.white.opacity(0.06) : Runway.green.opacity(0.12))
                )
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .pointerCursor()
        .help(active ? "Stand this crew down" : "Bring this crew up")
    }

    private func activate(_ crew: Binding<CrewPreview>) {
        withAnimation(.easeInOut(duration: 0.22)) {
            crew.wrappedValue.isActive = true
            reading = crew.wrappedValue.issueNumber
        }
    }

    private func standDown(_ crew: Binding<CrewPreview>) {
        withAnimation(.easeInOut(duration: 0.22)) {
            crew.wrappedValue.isActive = false
            if reading == crew.wrappedValue.issueNumber {
                reading = crews.first { $0.isActive }?.issueNumber
            }
        }
    }
}

/// How the active crews share the pane. Stood-down cards take their own line
/// first; what is left goes to the crews that are up, the one being read
/// taking two shares to everyone else's one.
enum CrewSpanPolicy {
    static let standingCardHeight: CGFloat = 69
    static let gap: CGFloat = 10
    static let minimumBox: CGFloat = 150

    static func spans(
        active: [Int],
        reading: Int?,
        paneHeight: CGFloat,
        standingCount: Int
    ) -> [Int: CGFloat] {
        guard !active.isEmpty else { return [:] }
        let rows = active.count + standingCount
        let chrome = 28 + gap * CGFloat(max(0, rows - 1))
            + standingCardHeight * CGFloat(standingCount)
        let free = max(paneHeight - chrome, CGFloat(active.count) * minimumBox)
        let readingIsUp = reading.map(active.contains) ?? false
        let shares = CGFloat(active.count) + (readingIsUp ? 1 : 0)
        return active.reduce(into: [:]) { spans, issue in
            let weight: CGFloat = (readingIsUp && issue == reading) ? 2 : 1
            spans[issue] = max(minimumBox, free * weight / shares)
        }
    }
}

// MARK: Placeholder

struct CrewPreview: Identifiable {
    enum State {
        case running
        case needsYou
        case idle

        var color: Color {
            switch self {
            case .running: Runway.green
            case .needsYou: Runway.amber
            case .idle: Color.white.opacity(0.3)
            }
        }
    }

    let issueNumber: Int
    let repository: String
    let title: String
    let branch: String
    let state: State
    var isActive: Bool

    var id: Int { issueNumber }

    static let sample: [CrewPreview] = [
        CrewPreview(issueNumber: 16257, repository: "monorepo",
                    title: "Booking form on the POS",
                    branch: "feat/pos-booking-form-16257",
                    state: .running, isActive: true),
        CrewPreview(issueNumber: 16261, repository: "monorepo",
                    title: "Hold a slot while paying",
                    branch: "feat/hold-slot-16261",
                    state: .needsYou, isActive: true),
        CrewPreview(issueNumber: 16264, repository: "monorepo",
                    title: "Refund a cancelled booking",
                    branch: "fix/refund-cancelled-16264",
                    state: .idle, isActive: false),
        CrewPreview(issueNumber: 16270, repository: "monorepo",
                    title: "Receipt shows the slot",
                    branch: "feat/receipt-slot-16270",
                    state: .idle, isActive: false),
    ]
}
