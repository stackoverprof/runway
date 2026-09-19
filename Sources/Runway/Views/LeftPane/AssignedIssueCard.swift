import AppKit
import SwiftUI

struct AssignedIssueCard: View {
    let issue: AssignedIssue
    let repository: String
    var onClosedChange: ((Bool) -> Void)? = nil
    var onRename: ((String) -> Void)? = nil
    var onRemoveFromFocus: (() -> Void)? = nil
    @State private var hovering = false
    @State private var isRenaming = false
    @State private var titleDraft = ""

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
                                    color: Self.openNSColor
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
                                    color: Self.closedNSColor
                                )
                            }
                        }
                    } label: {
                        statusIcon
                            .contentShape(Circle())
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
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

            if isRenaming {
                InlineField(
                    text: $titleDraft,
                    font: .systemFont(ofSize: 13.5, weight: .medium),
                    color: NSColor.white.withAlphaComponent(0.94),
                    placeholder: "Issue title",
                    onEnd: { finishRename() },
                    onCancel: { cancelRename() }
                )
                .frame(maxWidth: .infinity, minHeight: 19, alignment: .leading)
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.white.opacity(0.055))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.white.opacity(0.2), lineWidth: 1)
                )
            } else {
                Text(issue.title)
                    .font(.system(size: 13.5, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.94))
                    .multilineTextAlignment(.leading)
                    .lineLimit(3)
            }

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
        .contextMenu {
            if onRename != nil {
                Button("Rename issue") { beginRename() }
            }
            Button("Copy issue link") { copyIssueLink() }
            Button("Open link") { NSWorkspace.shared.open(issue.url) }
            if let onRemoveFromFocus {
                Divider()
                Button("Remove from focus") { onRemoveFromFocus() }
            }
        }
    }

    private func beginRename() {
        titleDraft = issue.title
        isRenaming = true
    }

    private func finishRename() {
        guard isRenaming else { return }
        let trimmed = titleDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        isRenaming = false
        titleDraft = trimmed
        guard !trimmed.isEmpty, trimmed != issue.title else { return }
        onRename?(trimmed)
    }

    private func cancelRename() {
        guard isRenaming else { return }
        isRenaming = false
        titleDraft = issue.title
    }

    private func copyIssueLink() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(issue.url.absoluteString, forType: .string)
    }

    private var statusIcon: some View {
        coloredMenuIcon(
            systemName: issue.isClosed ? "checkmark.circle" : "circle",
            color: issue.isClosed ? Self.closedNSColor : Self.openNSColor
        )
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
        return Image(nsImage: symbol).renderingMode(.original)
    }

    private static let openNSColor = NSColor(
        red: 0.18,
        green: 0.78,
        blue: 0.38,
        alpha: 1
    )

    private static let closedNSColor = NSColor(
        red: 0.64,
        green: 0.42,
        blue: 0.94,
        alpha: 1
    )
}
