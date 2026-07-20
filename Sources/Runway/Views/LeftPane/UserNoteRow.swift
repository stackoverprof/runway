import AppKit
import SwiftUI

/// A feed row for user-authored markdown notes.
struct UserNoteRow: View {
    let note: UserNote
    let time: String
    let isLast: Bool
    let agentFeed: AgentFeed
    @State private var hovering = false

    private static let accent = Color(red: 0.45, green: 0.82, blue: 0.78)

    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            ZStack(alignment: .top) {
                if !isLast {
                    Rectangle()
                        .fill(Color.white.opacity(0.08))
                        .frame(width: 1.5)
                        .frame(maxHeight: .infinity)
                        .padding(.top, 18)
                }
                // User icon instead of avatar
                ZStack {
                    Circle()
                        .fill(Self.accent.opacity(0.15))
                        .frame(width: 28, height: 28)
                    Image(systemName: "note.text")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Self.accent.opacity(0.7))
                }
                .padding(.top, 4)
            }
            .frame(width: 28)

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text("You")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(Self.accent.opacity(0.9))
                    Text("noted")
                        .font(.system(size: 12.5))
                        .foregroundStyle(Color.white.opacity(0.55))
                    Spacer(minLength: 6)
                    copyButton
                    deleteButton
                    pinButton
                    Text(time)
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(Color.white.opacity(0.3))
                }
                MarkdownBody(source: note.body)
            }
            .padding(11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(hovering ? 0.06 : 0.035)))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Self.accent.opacity(hovering ? 0.16 : 0.06), lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 10))
            .onHover { isHovering in
                withAnimation(.easeInOut(duration: 0.12)) { hovering = isHovering }
            }
            .padding(.bottom, 10)
        }
    }

    private var copyButton: some View {
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(note.body, forType: .string)
        } label: {
            Image(systemName: "doc.on.doc")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.5))
                .frame(width: 18, height: 18)
                .opacity(hovering ? 1 : 0)
        }
        .buttonStyle(.plain)
        .help("Copy note")
        .allowsHitTesting(hovering)
        .accessibilityHidden(!hovering)
    }

    private var pinButton: some View {
        Button {
            if note.pinned == true {
                agentFeed.unpinNote(id: note.id)
            } else {
                agentFeed.pinNote(id: note.id)
            }
        } label: {
            Image(systemName: note.pinned == true ? "pin.fill" : "pin")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(note.pinned == true ? Self.accent : Color.white.opacity(0.5))
                .frame(width: 18, height: 18)
                .opacity(hovering ? 1 : (note.pinned == true ? 0.7 : 0))
        }
        .buttonStyle(.plain)
        .help(note.pinned == true ? "Unpin note" : "Pin note")
        .allowsHitTesting(hovering || note.pinned == true)
        .accessibilityHidden(!hovering && note.pinned != true)
    }

    private var deleteButton: some View {
        Button {
            agentFeed.deleteNote(id: note.id)
        } label: {
            Image(systemName: "trash")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.5))
                .frame(width: 18, height: 18)
                .opacity(hovering ? 1 : 0)
        }
        .buttonStyle(.plain)
        .help("Delete note")
        .allowsHitTesting(hovering)
        .accessibilityHidden(!hovering)
    }
}
