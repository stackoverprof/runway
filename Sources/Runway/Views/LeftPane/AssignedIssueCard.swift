import AppKit
import SwiftUI

struct AssignedIssueCard: View {
    let issue: AssignedIssue
    let repository: String
    var onClosedChange: ((Bool) -> Void)? = nil
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 6) {
                if let onClosedChange {
                    Menu {
                        Button {
                            if issue.isClosed { onClosedChange(false) }
                        } label: {
                            Label {
                                Text("Open")
                            } icon: {
                                coloredMenuIcon(
                                    systemName: "circle",
                                    color: NSColor(
                                        red: 0.18,
                                        green: 0.78,
                                        blue: 0.38,
                                        alpha: 1
                                    )
                                )
                            }
                        }

                        Button {
                            if !issue.isClosed { onClosedChange(true) }
                        } label: {
                            Label {
                                Text("Closed")
                            } icon: {
                                coloredMenuIcon(
                                    systemName: "checkmark.circle",
                                    color: NSColor(
                                        red: 0.64,
                                        green: 0.42,
                                        blue: 0.94,
                                        alpha: 1
                                    )
                                )
                            }
                        }
                    } label: {
                        statusIcon
                            .contentShape(Circle())
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .tint(statusColor)
                    .fixedSize()
                    .pointerCursor()
                    .help("Change issue state")
                } else {
                    statusIcon
                }
                Text(verbatim: "\(repository) \(GitHubNumber.reference(issue.number))")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Color.white.opacity(0.52))
                    .lineLimit(1)
            }

            Text(issue.title)
                .font(.system(size: 13.5, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.94))
                .multilineTextAlignment(.leading)
                .lineLimit(3)

            if let closedAt = issue.closedAt {
                Text("Closed: \(closedAt.formatted(.dateTime.month(.abbreviated).day().year()))")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.52))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.white.opacity(0.09)))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 9)
                .fill(Color(white: hovering ? 0.09 : 0.075))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9)
                .stroke(
                    Color.white.opacity(hovering ? 0.24 : 0.14),
                    lineWidth: 1
                )
        )
        .contentShape(RoundedRectangle(cornerRadius: 9))
        .onHover { isHovering in
            hovering = isHovering
        }
        .pointerCursor()
        .onTapGesture {
            NSWorkspace.shared.open(issue.url)
        }
    }

    private var statusIcon: some View {
        Image(systemName: issue.isClosed ? "checkmark.circle" : "circle")
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(statusColor)
    }

    private func coloredMenuIcon(
        systemName: String,
        color: NSColor
    ) -> Image {
        let size = NSImage.SymbolConfiguration(pointSize: 13, weight: .medium)
        let palette = NSImage.SymbolConfiguration(paletteColors: [color])
        guard let symbol = NSImage(
            systemSymbolName: systemName,
            accessibilityDescription: nil
        )?.withSymbolConfiguration(size.applying(palette)) else {
            return Image(systemName: systemName)
        }
        symbol.isTemplate = false
        return Image(nsImage: symbol)
    }

    private var statusColor: Color {
        issue.isClosed ? closedColor : openColor
    }

    private var openColor: Color {
        Color(red: 0.18, green: 0.78, blue: 0.38)
    }

    private var closedColor: Color {
        Color(red: 0.64, green: 0.42, blue: 0.94)
    }

}
