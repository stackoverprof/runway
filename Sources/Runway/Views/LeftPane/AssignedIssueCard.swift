import AppKit
import SwiftUI

/// One issue in the Runway tab.
struct AssignedIssueCard: View {
    let issue: AssignedIssue
    let repository: String
    /// True when this is the issue the other two panes are answering for.
    var isFlying = false
    /// Open or close the issue from the card. Absent means no state menu.
    var onSetClosed: ((Bool) -> Void)?
    @State private var hovering = false
    private let board = FlightBoard.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 6) {
                if let onSetClosed {
                    Menu {
                        Button {
                            onSetClosed(false)
                        } label: {
                            Label("Open", systemImage: "circle")
                        }
                        Button {
                            onSetClosed(true)
                        } label: {
                            Label("Closed", systemImage: "checkmark.circle")
                        }
                    } label: {
                        statusIcon.contentShape(Circle())
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .pointerCursor()
                    .help("Open or close this issue")
                } else {
                    statusIcon
                }
                Text(verbatim: "\(repository) \(GitHubNumber.reference(issue.number))")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Color.white.opacity(0.52))
                    .lineLimit(1)

                Spacer(minLength: 6)

                priorityBadge

                // How the flight is doing, in the card's top corner, clear of
                // the name however long the name runs.
                if issue.isFlight {
                    Text("\(issue.landedLegs)/\(issue.legs.count) landed")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(Runway.teal.opacity(0.85))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Runway.teal.opacity(0.12)))
                        .fixedSize()
                }

                if let closedAt = issue.closedAt {
                    Text("Closed \(closedAt.formatted(.dateTime.month(.abbreviated).day().year()))")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.white.opacity(0.24))
                        .lineLimit(1)
                        .fixedSize()
                }

            }

            Text(issue.title)
                .font(.system(size: 13.5, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.94))
                .multilineTextAlignment(.leading)
                .lineLimit(3)

            if let parent = issue.parent {
                Text("crew of \(GitHubNumber.reference(parent))")
                    .font(.system(size: 9.5, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.3))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        // The flight on screen is the brighter card. No coloured ring: the
        // lift is enough, and it keeps every card the same shape.
        .background(
            RoundedRectangle(cornerRadius: 9)
                .fill(Color(white: isFlying ? 0.17 : (hovering ? 0.09 : 0.075)))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9)
                .stroke(
                    Color.white.opacity(isFlying ? 0.20 : (hovering ? 0.24 : 0.14)),
                    lineWidth: 1
                )
        )
        .contentShape(RoundedRectangle(cornerRadius: 9))
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
                        board.setPriority(level, for: issue.number, in: repository)
                    }
                }
                Divider()
                Button("None") { board.setPriority(nil, for: issue.number, in: repository) }
            }
        }
    }

    /// P1 to P5, red through blue, set from the badge itself.
    private var priorityBadge: some View {
        let level = board.priority(issue.number, in: repository)
        return Menu {
            ForEach(FlightPriority.all, id: \.self) { choice in
                Button(FlightPriority.label(choice)) {
                    board.setPriority(choice, for: issue.number, in: repository)
                }
            }
            Divider()
            Button("None") { board.setPriority(nil, for: issue.number, in: repository) }
        } label: {
            Text(level.map(FlightPriority.label) ?? "P–")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(
                    level.map { FlightPriority.color($0) } ?? Color.white.opacity(0.28)
                )
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    Capsule().fill(
                        (level.map { FlightPriority.color($0) } ?? Color.white)
                            .opacity(level == nil ? 0.05 : 0.14)
                    )
                )
                .fixedSize()
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .pointerCursor()
        .help("Set this flight's priority")
        .opacity(level == nil && !hovering ? 0 : 1)
    }

    private func copy(_ value: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }

    private var statusIcon: some View {
        let size = NSImage.SymbolConfiguration(pointSize: 13, weight: .medium)
        let color = issue.isClosed ? Self.closedNSColor : Self.openNSColor
        let palette = NSImage.SymbolConfiguration(paletteColors: [color])
        let name = issue.isClosed ? "checkmark.circle" : "circle"
        guard let symbol = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(size.applying(palette)) else {
            return Image(systemName: name).renderingMode(.original)
        }
        symbol.isTemplate = false
        return Image(nsImage: symbol).renderingMode(.original)
    }

    private static let openNSColor = NSColor(red: 0.18, green: 0.78, blue: 0.38, alpha: 1)
    private static let closedNSColor = NSColor(red: 0.64, green: 0.42, blue: 0.94, alpha: 1)
}
