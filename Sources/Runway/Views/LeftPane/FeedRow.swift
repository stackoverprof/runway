import AppKit
import SwiftUI

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
        case let .prMerged(number, _, _, _, _, _, _, _): return URL(string: "\(base)/pull/\(number)")
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
                        .padding(.top, 18)
                }
                Avatar(login: event.actor, url: event.avatarURL, size: 28)
                    .padding(.top, 4)
            }
            .frame(width: 28)

            // Card
            ZStack(alignment: .topLeading) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Text(PersonProfileManager.shared.username(for: event.actor))
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
            }
            .pointerCursor(link != nil)
            .onTapGesture { if let link { NSWorkspace.shared.open(link) } }
            .padding(.bottom, 10)
        }
    }

    private var isMergeEvent: Bool {
        if case .prMerged = event.kind { return true }
        return false
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
            prLine(GitHubNumber.reference(number), title.isEmpty ? branch : title, tint: Self.green)
        case let .prMerged(number, title, base, branch, adds, dels, commits, duration):
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Chip(GitHubNumber.reference(number), tint: Self.purple)
                    Image(systemName: "arrow.right").font(.system(size: 8, weight: .semibold)).foregroundStyle(Color.white.opacity(0.3))
                    Chip(base, tint: Self.gray)
                    if let a = adds, let d = dels {
                        Text("+\(a)").font(.system(size: 10.5, design: .monospaced)).foregroundStyle(Color(red: 0.4, green: 0.78, blue: 0.45).opacity(0.65))
                        Text("-\(d)").font(.system(size: 10.5, design: .monospaced)).foregroundStyle(Color(red: 0.95, green: 0.36, blue: 0.32).opacity(0.65))
                    }
                    if let c = commits {
                        Text("•").font(.system(size: 10)).foregroundStyle(Color.white.opacity(0.2))
                        Text("\(c) commit\(c == 1 ? "" : "s")").font(.system(size: 10.5, design: .monospaced)).foregroundStyle(Color.white.opacity(0.4))
                    }
                    if let dur = duration {
                        Text("•").font(.system(size: 10)).foregroundStyle(Color.white.opacity(0.2))
                        Text(PullRequestDurationFormatter.string(dur)).font(.system(size: 10.5, design: .monospaced)).foregroundStyle(Color.white.opacity(0.4))
                    }
                }
                Text(title.isEmpty ? branch : title).font(.system(size: 12)).foregroundStyle(Color.white.opacity(0.55)).lineLimit(1)
            }
        case let .branchCreated(name):
            Chip(name, tint: Self.green)
        case let .branchDeleted(name):
            Chip(name, tint: Self.gray)
        case let .review(number, title, state):
            prLine("\(GitHubNumber.reference(number)) \(state.lowercased())", title, tint: Self.blue)
        case let .issueOpened(number, title):
            prLine(GitHubNumber.reference(number), title, tint: Self.green)
        case let .issueClosed(number, title):
            prLine(GitHubNumber.reference(number), title, tint: Self.purple)
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
            // Opaque equivalent of the original translucent violet over the
            // app background. This restores the special merge treatment while
            // keeping every card fully solid.
            return hovering
                ? Color(red: 0.048, green: 0.027, blue: 0.112)
                : Color(red: 0.039, green: 0.022, blue: 0.090)
        }
        return Color(white: hovering ? 0.09 : 0.075)
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
