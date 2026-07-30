import AppKit
import SwiftUI

struct AssignedIssueCard: View {
    let issue: AssignedIssue
    let repository: String
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 6) {
                Image(systemName: issue.isClosed ? "checkmark.circle" : "circle")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(statusColor)
                Text("\(repository) #\(String(issue.number))")
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
                .fill(Color.white.opacity(hovering ? 0.06 : 0.035))
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
            if isHovering { NSCursor.pointingHand.set() } else { NSCursor.arrow.set() }
        }
        .onTapGesture {
            NSWorkspace.shared.open(issue.url)
        }
    }

    private var statusColor: Color {
        issue.isClosed
            ? Color(red: 0.64, green: 0.42, blue: 0.94)
            : Color(red: 0.18, green: 0.78, blue: 0.38)
    }

}
