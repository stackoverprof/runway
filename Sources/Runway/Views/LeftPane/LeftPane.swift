import SwiftUI
import AppKit

/// Left pane: a "working now" presence strip on top, then the activity stream.
struct LeftPane: View {
    @Bindable var ws: Workspace
    @Bindable var feed: GitHubFeed
    @Bindable var agentFeed: AgentFeed
    @State private var showRepoPicker = false
    @State private var showAllPresence = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if feed.events.isEmpty, let error = feed.lastError {
                // gh missing / not signed in / bad repo: explain, don't spin.
                feedNotice(error, systemImage: "exclamationmark.triangle")
            } else if feed.events.isEmpty, !feed.didLoad {
                // Genuinely still loading the first batch: skeletons (same shape
                // as the real content, so nothing jumps when data lands).
                skeletonPresence
                feedDivider
                skeletonStream
            } else if feed.events.isEmpty, agentFeed.posts.isEmpty {
                feedNotice("No recent activity in this repo yet.", systemImage: "tray")
            } else {
                if !feed.presence.isEmpty {
                    presenceStrip
                    feedDivider
                } else {
                    emptyOfficeNotice
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

    /// Centered message for the empty / error states (no gh, no repo, no events).
    private func feedNotice(_ message: String, systemImage: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 22, weight: .regular))
                .foregroundStyle(Color.white.opacity(0.3))
            Text(message)
                .font(.system(size: 13))
                .foregroundStyle(Color.white.opacity(0.6))
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.horizontal, 16)
        .padding(.top, 28)
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
            ForEach(showAllPresence ? feed.presence : Array(feed.presence.prefix(5))) { p in
                HStack(spacing: 8) {
                    Avatar(login: p.login, url: p.avatarURL, size: 18)
                    Text(PersonProfileManager.shared.displayName(for: p.login))
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(Color.white.opacity(p.idle ? 0.4 : 0.9))
                        .lineLimit(1)
                    Spacer(minLength: 6)
                    if p.idle {
                        Text("idle \(ago(p.lastActive))")
                            .font(.system(size: 10.5, design: .monospaced))
                            .foregroundStyle(Color.white.opacity(0.3))
                    } else {
                        Text(p.recentCount >= 5 ? "🔥 on fire" : "active")
                            .font(.system(size: 10.5, design: .monospaced))
                            .foregroundStyle(intensityColor(p.recentCount))
                    }
                }
            }
            // Beyond 5: a tappable row that expands to the full list (and collapses).
            if feed.presence.count > 5 {
                let overflow = Array(feed.presence.dropFirst(5))
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { showAllPresence.toggle() }
                } label: {
                    HStack(spacing: 8) {
                        if showAllPresence {
                            Text("show less")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(Color.white.opacity(0.4))
                        } else {
                            Text("+\(overflow.count) others")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(Color.white.opacity(0.4))
                            HStack(spacing: -6) {
                                ForEach(overflow.prefix(6)) { p in
                                    Avatar(login: p.login, url: p.avatarURL, size: 18)
                                        .overlay(Circle().stroke(Color(white: 0.035), lineWidth: 2))
                                }
                            }
                        }
                        Spacer(minLength: 6)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { if $0 { NSCursor.pointingHand.set() } else { NSCursor.arrow.set() } }
                .padding(.top, 2)
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }

    private func intensityColor(_ n: Int) -> Color {
        n >= 5 ? Color(red: 0.95, green: 0.55, blue: 0.25) : Color(red: 0.247, green: 0.725, blue: 0.314)
    }

    /// Placeholder when nobody is in the office.
    private var emptyOfficeNotice: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("OFFICE HOURS")
                .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                .foregroundStyle(Color.white.opacity(0.3))
                .tracking(0.8)
            HStack(spacing: 10) {
                Image(systemName: "moon.zzz")
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(Color.white.opacity(0.25))
                Text("Nobody in the office right now")
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.5))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }

    // MARK: Activity stream
    @State private var pulled = false

    private var stream: some View {
        let items = agentFeed.timeline(github: feed.events)
        return streamScaffold(disabled: false) {
            ForEach(items) { entry in
                switch entry {
                case let .github(event):
                    FeedRow(event: event, time: clock(event.date),
                        isLast: entry.id == items.last?.id, repo: feed.repo)
                        .transition(.move(edge: .top).combined(with: .opacity))
                case let .agent(post):
                    AgentFeedRow(post: post, time: clock(post.date),
                                 isLast: entry.id == items.last?.id,
                                 agentFeed: agentFeed)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            // Infinite scroll: a zero-height sentinel that loads the next page
            // when it scrolls into view (LazyVStack only renders it near the end).
            if feed.canLoadMore, !feed.events.isEmpty {
                Color.clear
                    .frame(height: 1)
                    .onAppear { Task { await feed.loadMore() } }
            }
            if feed.loadingMore {
                HStack {
                    Spacer()
                    ProgressView().controlSize(.small).scaleEffect(0.7)
                    Spacer()
                }
                .padding(.vertical, 10)
            }
            if !feed.canLoadMore, !feed.events.isEmpty {
                Text("END OF HISTORY — GITHUB KEEPS ~300 EVENTS")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.2))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
            }
        }
    }

    /// Shared scaffold for the real feed and the skeleton, so their caption and
    /// paddings are *identical* (including the overscroll sentinel, whose presence
    /// affects the top spacing — leaving it out made the skeleton caption ride up).
    private func streamScaffold<Rows: View>(disabled: Bool, @ViewBuilder rows: () -> Rows) -> some View {
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
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("WHAT YOUR TEAM'S BEEN HUSTLING, AS IT HAPPENS.")
                        .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Color.white.opacity(0.3))
                        .tracking(0.8)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    TimelineView(.periodic(from: .now, by: 60)) { ctx in
                        Text(dateClock(ctx.date))
                            .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                            .foregroundStyle(Color.white.opacity(0.2))
                            .tracking(0.8)
                            .fixedSize()
                    }
                }
                .padding(.bottom, 18)
                rows()
            }
            .padding(.horizontal, 16)
            .padding(.top, 6)
            .padding(.bottom, 16)
        }
        .scrollDisabled(disabled)
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
        streamScaffold(disabled: true) {
            ForEach(0..<7, id: \.self) { i in
                SkeletonRow(isLast: i == 6, seed: i)
            }
        }
    }

    /// Smart clock: today → "10.12", yesterday → "Yesterday 10.12",
    /// this week → "Fri 10.12", older → "21 Jun 10.12".
    private func clock(_ date: Date) -> String {
        let cal = Calendar.current
        let time = Self.clockFormatter.string(from: date)
        if cal.isDateInToday(date) {
            return time
        }
        if cal.isDateInYesterday(date) {
            return "Yesterday \(time)"
        }
        // Within 6 days → day name
        let daysAgo = cal.dateComponents([.day], from: cal.startOfDay(for: date), to: cal.startOfDay(for: Date())).day ?? 7
        if daysAgo < 7 {
            return "\(Self.dayNameFormatter.string(from: date)) \(time)"
        }
        return "\(Self.fullDateFormatter.string(from: date)) \(time)"
    }
    private static let clockFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "HH.mm"; return f
    }()
    private static let dayNameFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "EEE"; return f
    }()
    private static let fullDateFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "d MMM"; return f
    }()

    /// Full date + clock for the caption, e.g. "FRI 26 JUN 21.02".
    private func dateClock(_ date: Date) -> String { Self.dateClockFormatter.string(from: date).uppercased() }
    private static let dateClockFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "EEE d MMM HH.mm"; return f
    }()

    /// Relative duration, used for "idle 3h" in the presence strip.
    private func ago(_ date: Date) -> String {
        let s = Int(Date().timeIntervalSince(date))
        if s < 3600 { return "\(max(s / 60, 1))m" }
        if s < 86400 { return "\(s / 3600)h" }
        return "\(s / 86400)d"
    }
}
