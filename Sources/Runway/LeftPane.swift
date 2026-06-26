import SwiftUI

/// Left pane: a "working now" presence strip on top, then the activity stream.
struct LeftPane: View {
    @Bindable private var feed = GitHubFeed.shared
    @Bindable private var ws = Workspace.shared
    @State private var showRepoPicker = false

    /// First load (or repo switch) before any events arrive: show skeletons in
    /// the same shape as the real content so nothing jumps when data lands.
    private var isInitialLoad: Bool { feed.events.isEmpty && feed.lastError == nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if isInitialLoad {
                skeletonPresence
                feedDivider
                skeletonStream
            } else {
                if !feed.presence.isEmpty {
                    presenceStrip
                    feedDivider
                }
                stream
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(white: 0.035))
    }

    private var feedDivider: some View {
        Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1)
    }

    // MARK: Header
    private var header: some View {
        HStack(alignment: .center, spacing: 8) {
            Text("Activity")
                .font(.system(size: 27, weight: .bold))
                .foregroundStyle(Color.white.opacity(0.95))
            Spacer(minLength: 8)
            repoButton
        }
        .padding(.horizontal, 16)
        // Clear the traffic lights when windowed; tighten to the top in full screen.
        .padding(.top, ws.isFullScreen ? 18 : 50)
        .padding(.bottom, 22)
    }

    /// Rounded-rectangle repo selector with a repo glyph; opens a searchable picker.
    private var repoButton: some View {
        Button { showRepoPicker.toggle() } label: {
            HStack(spacing: 6) {
                Image(systemName: "book.closed.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.5))
                Text(feed.repo.split(separator: "/").last.map(String.init) ?? feed.repo)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(Color.white.opacity(0.4))
            }
            .foregroundStyle(Color.white.opacity(0.82))
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 7).fill(Color.white.opacity(0.07)))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.white.opacity(0.1), lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .onHover { if $0 { NSCursor.pointingHand.set() } else { NSCursor.arrow.set() } }
        .popover(isPresented: $showRepoPicker, arrowEdge: .bottom) {
            RepoPicker(repos: feed.availableRepos, current: feed.repo) { picked in
                feed.setRepo(picked)
                showRepoPicker = false
            }
        }
    }

    // MARK: Working-now strip
    private var presenceStrip: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("RECENTLY IN THE OFFICE")
                .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                .foregroundStyle(Color.white.opacity(0.3))
                .tracking(0.8)
            ForEach(feed.presence) { p in
                HStack(spacing: 8) {
                    Avatar(login: p.login, url: p.avatarURL, size: 18)
                    Text(p.login)
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(Color.white.opacity(p.idle ? 0.4 : 0.9))
                        .lineLimit(1)
                    Spacer(minLength: 6)
                    if p.idle {
                        Text("idle \(ago(p.lastActive))")
                            .font(.system(size: 10.5, design: .monospaced))
                            .foregroundStyle(Color.white.opacity(0.3))
                    } else {
                        Text(p.recentCount >= 5 ? "🔥 on a roll" : "active now")
                            .font(.system(size: 10.5, design: .monospaced))
                            .foregroundStyle(intensityColor(p.recentCount))
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }

    private func intensityColor(_ n: Int) -> Color {
        n >= 5 ? Color(red: 0.95, green: 0.55, blue: 0.25) : Color(red: 0.247, green: 0.725, blue: 0.314)
    }

    // MARK: Activity stream
    @State private var pulled = false

    private var stream: some View {
        ScrollView {
            // Overscroll-to-refresh: when pulled down past the top, refresh once.
            GeometryReader { geo in
                Color.clear
                    .frame(height: 0)
                    .onChange(of: geo.frame(in: .named("feed")).minY) { _, y in
                        if y < 4 { pulled = false }
                        if y > 64, !pulled { pulled = true; Task { await feed.refresh() } }
                    }
            }
            .frame(height: 0)

            LazyVStack(alignment: .leading, spacing: 0) {
                Text("WHAT YOUR TEAM'S BEEN HUSTLING, AS IT HAPPENS.")
                    .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.3))
                    .tracking(0.8)
                    .padding(.bottom, 18)
                ForEach(feed.events) { event in
                    FeedRow(event: event, time: clock(event.date),
                            isLast: event.id == feed.events.last?.id)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 6)
            .padding(.bottom, 16)
        }
        .scrollIndicators(.hidden)
        .coordinateSpace(name: "feed")
    }

    // MARK: Skeletons (initial load — same shape as the real content)

    private var skeletonPresence: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("RECENTLY IN THE OFFICE")
                .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                .foregroundStyle(Color.white.opacity(0.3))
                .tracking(0.8)
            ForEach(0..<4, id: \.self) { i in
                HStack(spacing: 8) {
                    SkeletonShape(.circle).frame(width: 18, height: 18)
                    SkeletonShape().frame(width: 78 - CGFloat(i * 8), height: 11)
                    Spacer(minLength: 6)
                    SkeletonShape().frame(width: 42, height: 9)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }

    private var skeletonStream: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                Text("WHAT YOUR TEAM'S BEEN HUSTLING, AS IT HAPPENS.")
                    .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.3))
                    .tracking(0.8)
                    .padding(.bottom, 18)
                ForEach(0..<7, id: \.self) { i in
                    SkeletonRow(isLast: i == 6, seed: i)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 6)
            .padding(.bottom, 16)
        }
        .scrollDisabled(true)
        .scrollIndicators(.hidden)
    }

    /// Absolute clock time, e.g. "10.12".
    private func clock(_ date: Date) -> String { Self.clockFormatter.string(from: date) }
    private static let clockFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "HH.mm"; return f
    }()

    /// Relative duration, used for "idle 3h" in the presence strip.
    private func ago(_ date: Date) -> String {
        let s = Int(Date().timeIntervalSince(date))
        if s < 3600 { return "\(max(s / 60, 1))m" }
        if s < 86400 { return "\(s / 3600)h" }
        return "\(s / 86400)d"
    }
}

// MARK: - Feed row

private struct FeedRow: View {
    let event: FeedEvent
    let time: String
    let isLast: Bool

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
                    .overlay(alignment: .bottomTrailing) {
                        Image(systemName: glyph)
                            .font(.system(size: 7, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 14, height: 14)
                            .background(Circle().fill(accent))
                            .overlay(Circle().stroke(Color(white: 0.035), lineWidth: 2))
                            .offset(x: 3, y: 3)
                    }
            }
            .frame(width: 28)

            // Card
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(event.actor)
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
                detail
            }
            .padding(11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.035)))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.06), lineWidth: 1))
            .padding(.bottom, 10)
        }
    }

    private var verb: String {
        switch event.kind {
        case .push: return "pushed"
        case .prOpened: return "opened PR"
        case .prMerged: return "merged"
        case .branchCreated: return "created branch"
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
        }
    }

    @ViewBuilder private var detail: some View {
        switch event.kind {
        case let .push(branch, commits):
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
}

// MARK: - Repo picker

/// Searchable, scrollable list of repos — far better than a 40-item native menu.
private struct RepoPicker: View {
    let repos: [String]
    let current: String
    let onPick: (String) -> Void
    @State private var query = ""

    private var filtered: [String] {
        query.isEmpty ? repos : repos.filter { $0.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").font(.system(size: 11)).foregroundStyle(.secondary)
                TextField("Search repos…", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12.5))
            }
            .padding(.horizontal, 12).padding(.vertical, 9)
            Divider()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(filtered, id: \.self) { r in
                        Button { onPick(r) } label: {
                            HStack(spacing: 8) {
                                Text(r.split(separator: "/").last.map(String.init) ?? r)
                                    .font(.system(size: 12.5, design: .monospaced))
                                    .foregroundStyle(.primary)
                                Spacer(minLength: 8)
                                if r == current {
                                    Image(systemName: "checkmark").font(.system(size: 10, weight: .bold))
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.horizontal, 12).padding(.vertical, 7)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    if filtered.isEmpty {
                        Text(repos.isEmpty ? "Loading repos…" : "No matches")
                            .font(.system(size: 12)).foregroundStyle(.secondary)
                            .padding(12)
                    }
                }
            }
            .frame(maxHeight: 320)
        }
        .frame(width: 270)
    }
}

// MARK: - Bits

private struct Chip: View {
    let text: String; let tint: Color
    init(_ text: String, tint: Color) { self.text = text; self.tint = tint }
    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .medium, design: .monospaced))
            .foregroundStyle(tint)
            .lineLimit(1)
            .padding(.horizontal, 7).padding(.vertical, 2.5)
            .background(RoundedRectangle(cornerRadius: 5).fill(tint.opacity(0.14)))
            .overlay(RoundedRectangle(cornerRadius: 5).stroke(tint.opacity(0.25), lineWidth: 1))
    }
}

private struct Avatar: View {
    let login: String
    var url: String? = nil
    let size: CGFloat

    var body: some View {
        Group {
            if let url, let u = URL(string: url) {
                AsyncImage(url: u) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFill()
                    } else {
                        initialsCircle
                    }
                }
            } else {
                initialsCircle
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }

    private var initialsCircle: some View {
        Circle()
            .fill(LinearGradient(colors: [color, color.opacity(0.7)], startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay(Text(initials).font(.system(size: size * 0.38, weight: .bold)).foregroundStyle(.white))
    }
    private var initials: String { String(login.prefix(2)).uppercased() }
    private var color: Color {
        let h = abs(login.hashValue)
        return Color(hue: Double(h % 360) / 360, saturation: 0.5, brightness: 0.65)
    }
}

// MARK: - Skeleton primitives

/// A softly pulsing placeholder block (bar or circle), used during initial load.
private struct SkeletonShape: View {
    enum Kind { case bar, circle }
    let kind: Kind
    @State private var pulse = false
    init(_ kind: Kind = .bar) { self.kind = kind }

    var body: some View {
        Group {
            switch kind {
            case .circle: Circle().fill(fill)
            case .bar: RoundedRectangle(cornerRadius: 4).fill(fill)
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.95).repeatForever(autoreverses: true)) { pulse = true }
        }
    }
    private var fill: Color { Color.white.opacity(pulse ? 0.11 : 0.045) }
}

/// A skeleton timeline card matching `FeedRow`'s layout, so real rows replacing
/// these don't shift the surrounding content.
private struct SkeletonRow: View {
    let isLast: Bool
    let seed: Int

    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            ZStack(alignment: .top) {
                if !isLast {
                    Rectangle().fill(Color.white.opacity(0.06))
                        .frame(width: 1.5).frame(maxHeight: .infinity)
                }
                // Opaque base so the rail line passes *under* the node (the real
                // avatar is opaque; the skeleton fill alone is translucent).
                SkeletonShape(.circle)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(Color(white: 0.035)))
            }
            .frame(width: 28)

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    SkeletonShape().frame(width: 70, height: 11)
                    SkeletonShape().frame(width: 46, height: 11)
                    Spacer(minLength: 6)
                    SkeletonShape().frame(width: 30, height: 9)
                }
                SkeletonShape().frame(width: 120 + CGFloat((seed % 3) * 34), height: 16)
            }
            .padding(11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.02)))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.05), lineWidth: 1))
            .padding(.bottom, 10)
        }
    }
}
