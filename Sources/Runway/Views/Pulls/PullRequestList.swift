import AppKit
import SwiftUI

/// The Pulls list, in one place.
///
/// The left pane shows a developer's pull requests and a flight shows its
/// own; they are the same list and should read the same, so both sides use
/// this view rather than each drawing its own rows.
struct PullRequestList: View {
    /// The pull requests to show, in whatever order the caller wants them.
    let pullRequests: [RepositoryPullRequest]
    /// Namespaces this list's paging, so two lists on screen page apart. Its
    /// change also resets the paging, which is what a repository switch wants.
    let scope: String
    /// How many to show before "show next".
    var pageSize: Int = 20

    @State private var visible: [String: Int] = [:]
    @State private var expanded: Set<Int> = []

    static let green = Color(red: 0.18, green: 0.78, blue: 0.38)
    static let orange = Color(red: 0.94, green: 0.62, blue: 0.20)
    static let purple = Color(red: 0.64, green: 0.42, blue: 0.94)
    static let closed = Color.white.opacity(0.38)

    var body: some View {
        // A stack sits in the section of its bottom PR, the one next to merge,
        // even when the PRs above it are drafts.
        let open = PRStackItem.items(pullRequests.filter(\.isOpen))
        VStack(alignment: .leading, spacing: 10) {
            section("DRAFT", items: open.filter { $0.bottom.isDraft }, color: Self.orange)
            section("OPEN", items: open.filter { !$0.bottom.isDraft }, color: Self.green)
            section(
                "MERGED",
                items: pullRequests.filter(\.isMerged).map(PRStackItem.single),
                color: Self.purple
            )
            section(
                "CLOSED",
                items: pullRequests.filter { !$0.isOpen && !$0.isMerged }.map(PRStackItem.single),
                color: Self.closed
            )
        }
        .onChange(of: scope) { _, _ in
            visible.removeAll()
            expanded.removeAll()
        }
    }

    @ViewBuilder
    private func section(_ title: String, items: [PRStackItem], color: Color) -> some View {
        if !items.isEmpty {
            let key = "\(scope)/\(title)"
            let shown = min(visible[key] ?? pageSize, items.count)
            let remaining = items.count - shown
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 5) {
                    Circle().fill(color).frame(width: 5, height: 5)
                    Text("\(title)  \(items.reduce(0) { $0 + $1.pullRequests.count })")
                        .font(.system(size: 8.5, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Color.white.opacity(0.32))
                    Spacer()
                    if remaining > 0 {
                        Text("SHOWING \(shown)")
                            .font(.system(size: 7.5, weight: .medium, design: .monospaced))
                            .foregroundStyle(Color.white.opacity(0.20))
                    }
                }
                ForEach(Array(items.prefix(shown))) { item in
                    switch item {
                    case .single(let pullRequest): row(pullRequest, color: color)
                    case .stack(let stack): stackView(stack, color: color)
                    }
                }
                if remaining > 0 {
                    Button {
                        withAnimation(.easeInOut(duration: 0.16)) {
                            visible[key] = min(shown + pageSize, items.count)
                        }
                    } label: {
                        HStack {
                            Text("Show next \(min(pageSize, remaining))")
                            Spacer()
                            Text("\(remaining) remaining")
                                .foregroundStyle(Color.white.opacity(0.24))
                        }
                        .font(.system(size: 8.5, weight: .medium, design: .monospaced))
                        .foregroundStyle(Color.white.opacity(0.45))
                        .padding(.horizontal, 8)
                        .frame(height: 26)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.025)))
                        .contentShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                    .pointerCursor()
                }
            }
        }
    }

    func row(_ pullRequest: RepositoryPullRequest, color: Color) -> some View {
        Button {
            NSWorkspace.shared.open(pullRequest.url)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 7) {
                    Text(verbatim: GitHubNumber.reference(pullRequest.number))
                        .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                        .foregroundStyle(color.opacity(0.82))
                    if pullRequest.isDraft {
                        Text("DRAFT")
                            .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                            .foregroundStyle(Color.white.opacity(0.38))
                    }
                    Text(pullRequest.title)
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.70))
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    if let timeframe = Self.timeframe(pullRequest) {
                        Text(timeframe)
                            .font(.system(size: 8.5, design: .monospaced))
                            .foregroundStyle(Color.white.opacity(0.24))
                    }
                }
                HStack(spacing: 5) {
                    BranchNameText(name: pullRequest.headRefName)
                    Image(systemName: "arrow.right")
                        .font(.system(size: 7, weight: .semibold))
                    BranchNameText(name: pullRequest.baseRefName)
                }
                .font(.system(size: 8.5, design: .monospaced))
                .foregroundStyle(Color.white.opacity(0.27))
                .lineLimit(1)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.025)))
            .contentShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .pointerCursor()
        .contextMenu {
            Button("Copy PR link") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(pullRequest.url.absoluteString, forType: .string)
            }
            Button("Open PR link") { NSWorkspace.shared.open(pullRequest.url) }
        }
    }

    /// A stack as a deck: collapsed, the top PR with the others peeking out
    /// beneath it; tapped, it fans out top to bottom with a line down the side.
    @ViewBuilder
    private func stackView(_ stack: [RepositoryPullRequest], color: Color) -> some View {
        let bottom = stack[stack.count - 1]
        let isOpen = expanded.contains(bottom.number)
        VStack(alignment: .leading, spacing: 5) {
            Button {
                withAnimation(.spring(response: 0.30, dampingFraction: 0.86)) {
                    if isOpen { expanded.remove(bottom.number) } else { expanded.insert(bottom.number) }
                }
            } label: {
                if isOpen {
                    stackHeader(stack, color: color, expanded: true)
                } else {
                    stackDeck(stack, color: color)
                }
            }
            .buttonStyle(.plain)
            .pointerCursor()
            .help(isOpen ? "Collapse the stack" : "Show all \(stack.count) PRs in the stack")

            if isOpen {
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(stack) { pullRequest in
                        row(pullRequest, color: pullRequest.isDraft ? Self.orange : Self.green)
                    }
                }
                .padding(.leading, 9)
                .overlay(alignment: .leading) {
                    Rectangle()
                        .fill(color.opacity(0.35))
                        .frame(width: 1.5)
                        .padding(.vertical, 6)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private func stackHeader(
        _ stack: [RepositoryPullRequest],
        color: Color,
        expanded isOpen: Bool
    ) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "square.stack.3d.up.fill")
                .font(.system(size: 8.5, weight: .semibold))
                .foregroundStyle(color.opacity(0.82))
            Text("STACK OF \(stack.count)")
                .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                .foregroundStyle(Color.white.opacity(0.55))
            Text("on \(stack[stack.count - 1].baseRefName)")
                .font(.system(size: 8.5, design: .monospaced))
                .foregroundStyle(Color.white.opacity(0.27))
                .lineLimit(1)
            Spacer(minLength: 4)
            Image(systemName: "chevron.down")
                .font(.system(size: 7.5, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.30))
                .rotationEffect(.degrees(isOpen ? 180 : 0))
        }
        .padding(.horizontal, 8)
        .frame(height: 22)
        .contentShape(Rectangle())
    }

    /// The top PR's card, with one edge per hidden PR (two at most) under it.
    private func stackDeck(_ stack: [RepositoryPullRequest], color: Color) -> some View {
        let top = stack[0]
        let edges = min(stack.count - 1, 2)
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 7) {
                Text(verbatim: GitHubNumber.reference(top.number))
                    .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                    .foregroundStyle(color.opacity(0.82))
                Text(top.title)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.70))
                    .lineLimit(1)
                Spacer(minLength: 4)
                if let timeframe = Self.timeframe(top) {
                    Text(timeframe)
                        .font(.system(size: 8.5, design: .monospaced))
                        .foregroundStyle(Color.white.opacity(0.24))
                }
            }
            HStack(spacing: 5) {
                Image(systemName: "square.stack.3d.up.fill")
                    .font(.system(size: 7.5, weight: .semibold))
                    .foregroundStyle(color.opacity(0.7))
                Text("STACK OF \(stack.count)")
                    .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.45))
                Text("· on \(stack[stack.count - 1].baseRefName)")
                    .lineLimit(1)
            }
            .font(.system(size: 8.5, design: .monospaced))
            .foregroundStyle(Color.white.opacity(0.27))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color(white: 0.105)))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.white.opacity(0.08), lineWidth: 1))
        .background(alignment: .bottom) {
            VStack(spacing: 0) {
                ForEach(0..<edges, id: \.self) { edge in
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(white: 0.085))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.white.opacity(0.07), lineWidth: 1)
                        )
                        .frame(height: 10)
                        .padding(.horizontal, CGFloat(edge + 1) * 5)
                        .offset(y: CGFloat(edge + 1) * 4)
                }
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 6))
    }

    static func timeframe(_ pullRequest: RepositoryPullRequest) -> String? {
        if pullRequest.isMerged {
            let mergedAt = pullRequest.mergedAt ?? pullRequest.closedAt ?? pullRequest.updatedAt
            return "merged \(relative(mergedAt))"
        }
        guard pullRequest.isOpen, !pullRequest.isDraft else { return nil }
        return PullRequestDurationFormatter.string(Date().timeIntervalSince(pullRequest.createdAt))
    }

    private static func relative(_ date: Date) -> String {
        let seconds = max(0, Int(Date().timeIntervalSince(date)))
        if seconds < 60 { return "just now" }
        let minutes = seconds / 60
        if minutes == 1 { return "a minute ago" }
        if minutes < 60 { return "\(minutes) minutes ago" }
        let hours = minutes / 60
        if hours == 1 { return "an hour ago" }
        if hours < 24 { return "\(hours) hours ago" }
        let formatter = DateFormatter()
        formatter.dateFormat = "d MMM"
        return formatter.string(from: date)
    }
}

/// A branch name that keeps its trailing issue number when it is too long:
/// `feat/designer-image-only-saves-16283` shows as `feat/designer-ima…-16283`.
struct BranchNameText: View {
    let name: String

    var body: some View {
        let parts = BranchIssue.split(name)
        HStack(spacing: 0) {
            Text(parts.stem)
                .truncationMode(.tail)
            if let number = parts.number {
                Text(number)
                    .fixedSize()
            }
        }
        .lineLimit(1)
    }
}
