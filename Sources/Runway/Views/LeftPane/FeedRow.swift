import SwiftUI

struct AgentFeedRow: View {
    let post: AgentPost
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
                }
                Avatar(login: post.author, size: 28)
            }
            .frame(width: 28)

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(PersonProfileManager.shared.displayName(for: post.author))
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.9))
                    Text("posted")
                        .font(.system(size: 12.5))
                        .foregroundStyle(Color.white.opacity(0.55))
                    Spacer(minLength: 6)
                    deleteButton
                    Text(time)
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(Color.white.opacity(0.3))
                }
                if let title = post.title, !title.isEmpty {
                    Text(title)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.78))
                }
                MarkdownBody(source: post.body)
            }
            .padding(11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(hovering ? 0.06 : 0.035)))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(hovering ? 0.12 : 0.06), lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 10))
            .onHover { isHovering in
                withAnimation(.easeInOut(duration: 0.12)) { hovering = isHovering }
            }
            .padding(.bottom, 10)
        }
    }

    private var deleteButton: some View {
        Button {
            agentFeed.deletePost(id: post.id)
        } label: {
            Image(systemName: "trash")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.5))
                .frame(width: 18, height: 18)
                .opacity(hovering ? 1 : 0)
        }
        .buttonStyle(.plain)
        .help("Delete post")
        .allowsHitTesting(hovering)
        .accessibilityHidden(!hovering)
    }
}

struct FeedRow: View {
    let event: FeedEvent
    let time: String
    let isLast: Bool
    let repo: String
    @State private var hovering = false

    /// The GitHub page this event points at.
    private var link: URL? {
        let base = "https://github.com/\(repo)"
        switch event.kind {
        case let .push(branch, _, _):        return URL(string: "\(base)/commits/\(branch)")
        case let .prOpened(number, _, _):    return URL(string: "\(base)/pull/\(number)")
        case let .prMerged(number, _, _, _, _, _): return URL(string: "\(base)/pull/\(number)")
        case let .branchCreated(name):       return URL(string: "\(base)/tree/\(name)")
        case .branchDeleted:                 return URL(string: "\(base)/branches")
        case let .review(number, _, _):      return URL(string: "\(base)/pull/\(number)")
        case let .issueOpened(number, _):    return URL(string: "\(base)/issues/\(number)")
        case let .issueClosed(number, _):    return URL(string: "\(base)/issues/\(number)")
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            // Timeline rail: a connecting line with the avatar as the node.
            ZStack(alignment: .top) {
                if !isLast {
                    Rectangle()
                        .fill(Color.white.opacity(0.08))
                        .frame(width: 1.5)
                        .frame(maxHeight: .infinity)
                }
                Avatar(login: event.actor, url: event.avatarURL, size: 28)
            }
            .frame(width: 28)

            // Card
            ZStack(alignment: .topLeading) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Text(PersonProfileManager.shared.displayName(for: event.actor))
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(Color.white.opacity(0.9))
                        Text(verb)
                            .font(.system(size: 12.5))
                            .foregroundStyle(Color.white.opacity(0.55))
                        Spacer(minLength: 6)
                        Text(time)
                            .font(.system(size: 10.5, design: .monospaced))
                            .foregroundStyle(Color.white.opacity(0.3))
                    }
                    
                    // Wider gap for merge events
                    if case .prMerged = event.kind {
                        Spacer().frame(height: 20)
                    } else {
                        Spacer().frame(height: 6)
                    }
                    
                    detail
                }
                .padding(11)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(cardBackground)
            .overlay(alignment: .top) {
                if case .prMerged = event.kind {
                    LinearGradient(
                        gradient: Gradient(colors: [
                            Self.purple.opacity(0.12),
                            Color.clear
                        ]),
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .allowsHitTesting(false)
                }
            }
            .overlay(cardBorder)
            .contentShape(RoundedRectangle(cornerRadius: 10))
            .onHover { h in
                hovering = h
                if h, link != nil { NSCursor.pointingHand.set() } else { NSCursor.arrow.set() }
            }
            .onTapGesture { if let link { NSWorkspace.shared.open(link) } }
            .padding(.bottom, 10)
        }
    }

    private var verb: String {
        switch event.kind {
        case let .push(_, count, _):
            guard let count else { return "pushed" }
            return "pushed \(count) commit\(count == 1 ? "" : "s")"
        case .prOpened: return "opened PR"
        case .prMerged: return "merged"
        case .branchCreated: return "created branch"
        case .branchDeleted: return "deleted branch"
        case .review: return "reviewed"
        case .issueOpened: return "opened issue"
        case .issueClosed: return "closed issue"
        }
    }
    private var glyph: String {
        switch event.kind {
        case .push: return "arrow.up"
        case .prOpened: return "arrow.triangle.pull"
        case .prMerged: return "arrow.triangle.merge"
        case .branchCreated: return "arrow.triangle.branch"
        case .branchDeleted: return "trash"
        case .review: return "checkmark"
        case .issueOpened: return "exclamationmark"
        case .issueClosed: return "checkmark"
        }
    }
    // Semantic palette: creation = green, progress/push = blue, closure/merge = purple.
    static let green = Color(red: 0.30, green: 0.73, blue: 0.42)
    static let blue = Color(red: 0.35, green: 0.55, blue: 0.94)
    static let gray = Color(red: 0.50, green: 0.53, blue: 0.58)
    static let purple = Color(red: 0.62, green: 0.40, blue: 0.92)

    private var accent: Color {
        switch event.kind {
        case .prOpened, .branchCreated, .issueOpened: return Self.green
        case .push, .review: return Self.blue
        case .prMerged, .issueClosed: return Self.purple
        case .branchDeleted: return Self.gray
        }
    }

    @ViewBuilder private var detail: some View {
        switch event.kind {
        case let .push(branch, _, commits):
            VStack(alignment: .leading, spacing: 6) {
                Chip(branch, tint: Self.blue)
                ForEach(commits.prefix(3)) { c in
                    HStack(alignment: .firstTextBaseline, spacing: 7) {
                        Text(c.sha).font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(Color.white.opacity(0.4))
                        Text(c.message).font(.system(size: 12)).foregroundStyle(Color.white.opacity(0.55)).lineLimit(1)
                    }
                }
            }
        case let .prOpened(number, title, branch):
            prLine("#\(number)", title.isEmpty ? branch : title, tint: Self.green)
        case let .prMerged(number, title, base, branch, adds, dels):
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Chip("#\(number)", tint: Self.purple)
                    Image(systemName: "arrow.right").font(.system(size: 8, weight: .semibold)).foregroundStyle(Color.white.opacity(0.3))
                    Chip(base, tint: Self.gray)
                    if let a = adds, let d = dels {
                        Text("+\(a)").font(.system(size: 10.5, design: .monospaced)).foregroundStyle(Color(red: 0.4, green: 0.78, blue: 0.45))
                        Text("-\(d)").font(.system(size: 10.5, design: .monospaced)).foregroundStyle(Color(red: 0.95, green: 0.36, blue: 0.32))
                    }
                }
                Text(title.isEmpty ? branch : title).font(.system(size: 12)).foregroundStyle(Color.white.opacity(0.55)).lineLimit(1)
            }
        case let .branchCreated(name):
            Chip(name, tint: Self.green)
        case let .branchDeleted(name):
            Chip(name, tint: Self.gray)
        case let .review(number, title, state):
            prLine("#\(number) \(state.lowercased())", title, tint: Self.blue)
        case let .issueOpened(number, title):
            prLine("#\(number)", title, tint: Self.green)
        case let .issueClosed(number, title):
            prLine("#\(number)", title, tint: Self.purple)
        }
    }

    private func prLine(_ tag: String, _ title: String, tint: Color) -> some View {
        HStack(spacing: 7) {
            Chip(tag, tint: tint)
            Text(title).font(.system(size: 12)).foregroundStyle(Color.white.opacity(0.55)).lineLimit(1)
        }
    }

    private var cardBackgroundColor: Color {
        if case .prMerged = event.kind {
            return Color(red: 0.04, green: 0.02, blue: 0.10).opacity(hovering ? 0.95 : 0.85)
        } else {
            return Color.white.opacity(hovering ? 0.06 : 0.035)
        }
    }

    private var cardBorderColor: Color {
        if case .prMerged = event.kind {
            return Self.purple.opacity(hovering ? 0.22 : 0.10)
        } else {
            return Color.white.opacity(hovering ? 0.16 : 0.06)
        }
    }

    private var cardBackground: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10).fill(cardBackgroundColor)
            if case .prMerged = event.kind {
                MergeCardDecorations()
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
    }

    private var cardBorder: some View {
        RoundedRectangle(cornerRadius: 10).stroke(cardBorderColor, lineWidth: 1)
    }
}
