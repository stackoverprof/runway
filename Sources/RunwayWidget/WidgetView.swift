import AppKit
import SwiftUI

/// Runway's left pane, alone: who's around, my open issues, the repo feed and
/// pull requests by developer. Same look as Runway v3, no agents.
enum WidgetTab: String, CaseIterable {
    case runway = "Runway"
    case feeds = "Feeds"
    case pullRequests = "Pulls"

    var index: Int { Self.allCases.firstIndex(of: self) ?? 0 }
}

enum PRTimeframe: String, CaseIterable, Identifiable {
    case oneDay = "24h", sevenDays = "7d", thirtyDays = "30d", monthToDate = "MTD", yearToDate = "YTD"
    var id: String { rawValue }

    func startDate(now: Date = Date(), calendar: Calendar = .current) -> Date {
        switch self {
        case .oneDay: now.addingTimeInterval(-86_400)
        case .sevenDays: now.addingTimeInterval(-7 * 86_400)
        case .thirtyDays: now.addingTimeInterval(-30 * 86_400)
        case .monthToDate: calendar.dateInterval(of: .month, for: now)?.start ?? now
        case .yearToDate: calendar.dateInterval(of: .year, for: now)?.start ?? now
        }
    }
}

struct WidgetView: View {
    @State private var feed = GitHubFeed.shared
    @State private var pulls = PullRequests.shared
    @State private var issues = AssignedIssues.shared
    @AppStorage("widget.tab") private var selectedTab: WidgetTab = .runway
    @AppStorage("widget.prTimeframe") private var prTimeframe: PRTimeframe = .monthToDate
    @AppStorage(SettingsKey.fireThreshold) private var fireThreshold = 5
    @State private var showAllPresence = false
    @State private var expandedPRAuthor: String?
    /// Cluster stacks fanned out, by cluster name.
    @AppStorage("widget.expandedClusters") private var expandedClustersRaw = ""
    /// The live set. @AppStorage drops the animation transaction, so the
    /// view animates off this and the raw string only persists it.
    @State private var openClusters: Set<String>?
    @State private var started = false
    @State private var showRepoPicker = false
    @State private var organizations: [String] = [GitHubFeed.shared.organization]
    @AppStorage("widget.mergesOnly") private var mergesOnly = false
    /// The keyboard cursor in the tab in front.
    @State private var cursor: NavItem?
    /// Issues showing their PRs, by issue id.
    @State private var openIssues: Set<String> = []
    @State private var keyMonitor: Any?
    /// Bumped to send the tab in front back to its top.
    @State private var scrollTopTick = 0
    /// The cursor only shows while you drive with the keyboard; touching the
    /// mouse hides it until the next key.
    @State private var keyboardActive = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if feed.events.isEmpty, let error = feed.lastError {
                notice(error, systemImage: "exclamationmark.triangle")
            } else {
                if !feed.presence.isEmpty {
                    presenceStrip
                    divider
                } else if feed.didLoad {
                    emptyOfficeNotice
                    divider
                }
                subHeader
                slidingTabContent
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear(perform: start)
        .onAppear(perform: installKeys)
        .task { await loadOrganizations() }
        // The panel's view lives on between openings: refresh on each one.
        .onReceive(NotificationCenter.default.publisher(for: .widgetShown)) { _ in start() }
        .onChange(of: selectedTab) { _, _ in cursor = nil }
        .task(id: feed.repo) {
            expandedPRAuthor = nil
            pulls.restore(repository: feed.repo)
            await pulls.revalidate(repository: feed.repo, minimumAge: 30)
        }
    }

    private func start() {
        if !started {
            started = true
            feed.startPolling()
            issues.startPolling(every: 60)
            pulls.restore(repository: feed.repo)
            // CI of the PRs under my issues, for the PR count's colour.
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 3 * 1_000_000_000)
                while !Task.isCancelled {
                    let urls = issues.clusterPulls.values.flatMap { $0 }.filter { !$0.isDraft }.map(\.url)
                    await PullChecks.shared.refresh(urls)
                    try? await Task.sleep(nanoseconds: 45 * 1_000_000_000)
                }
            }
            // PRs merge and open all day; keep the counts current.
            Task { @MainActor in
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 60 * 1_000_000_000)
                    await pulls.revalidate(repository: feed.repo, minimumAge: 30)
                }
            }
        }
        Task { await feed.refresh(minimumAge: 30) }
        Task { await pulls.revalidate(repository: feed.repo, minimumAge: 60) }
        Task { await issues.refresh() }
    }

    private var divider: some View {
        Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1)
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .center, spacing: 8) {
            Text("RECENTLY IN THE OFFICE")
                .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                .foregroundStyle(Color.white.opacity(0.3))
                .tracking(0.8)
                .lineLimit(1)
            Spacer(minLength: 8)
            Menu {
                Menu("Organization: \(feed.organization)") {
                    ForEach(organizations, id: \.self) { org in
                        Button {
                            feed.setOrganization(org)
                        } label: {
                            if org == feed.organization { Label(org, systemImage: "checkmark") } else { Text(org) }
                        }
                    }
                }
                Divider()
                Button("Refresh") { start() }
                Divider()
                Button("Quit Runway Widget") {
                    WidgetAppDelegate.quitChosen = true
                    NSApp.terminate(nil)
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.5))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 10)
    }

    private func loadOrganizations() async {
        guard organizations.count <= 1,
              let data = await GH.api("/user/orgs", cacheFor: 3_600),
              let rows = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return }
        let found = rows.compactMap { $0["login"] as? String }
        if !found.isEmpty { organizations = found }
    }

    // MARK: Recently in the office

    private var presenceStrip: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(showAllPresence ? feed.presence : Array(feed.presence.prefix(5))) { p in
                HStack(spacing: 8) {
                    Avatar(login: p.login, url: p.avatarURL, size: 18)
                    Text(PersonProfileManager.shared.username(for: p.login))
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(Color.white.opacity(p.idle ? 0.4 : 0.9))
                        .lineLimit(1)
                    Spacer(minLength: 6)
                    if p.idle {
                        Text("idle \(ago(p.lastActive))")
                            .font(.system(size: 10.5, design: .monospaced))
                            .foregroundStyle(Color.white.opacity(0.3))
                    } else {
                        Text(p.recentCount >= fireThreshold ? "🔥 on fire" : "active")
                            .font(.system(size: 10.5, design: .monospaced))
                            .foregroundStyle(intensityColor(p.recentCount))
                    }
                }
            }
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
                            Text(verbatim: "+\(overflow.count) others")
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
                .padding(.top, 2)
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }

    private func intensityColor(_ n: Int) -> Color {
        n >= 5 ? Color(red: 0.95, green: 0.55, blue: 0.25) : Color(red: 0.247, green: 0.725, blue: 0.314)
    }

    private var emptyOfficeNotice: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: "moon.zzz")
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(Color.white.opacity(0.25))
                Text("Nobody in the office right now")
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.5))
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 10)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }

    // MARK: Tabs

    private var subHeader: some View {
        HStack(alignment: .center, spacing: 8) {
            Text(subHeaderText)
            Spacer(minLength: 8)
            tabSwitch
        }
        .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
        .foregroundStyle(Color.white.opacity(0.3))
        .tracking(0.8)
        .lineLimit(1)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var subHeaderText: String {
        switch selectedTab {
        case .runway: "ON TODAY'S MISSIONS"
        case .feeds: "WHAT HAS BEEN HAPPENING"
        case .pullRequests: "PULL REQUESTS BY DEV"
        }
    }

    private var tabSwitch: some View {
        HStack(spacing: 0) {
            ForEach(WidgetTab.allCases, id: \.rawValue) { tab in
                Button {
                    selectTab(tab)
                } label: {
                    Text(tab.rawValue)
                        .font(.system(size: 10, weight: selectedTab == tab ? .semibold : .medium, design: .monospaced))
                        .foregroundStyle(selectedTab == tab ? Color.white.opacity(0.9) : Color.white.opacity(0.35))
                        .fixedSize(horizontal: true, vertical: false)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 5)
                                .fill(selectedTab == tab ? Color.white.opacity(0.1) : Color.clear)
                        )
                        .contentShape(RoundedRectangle(cornerRadius: 5))
                }
                .buttonStyle(.plain)
            }
        }
        .fixedSize(horizontal: true, vertical: false)
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 7).fill(Color.white.opacity(0.04)))
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.white.opacity(0.06), lineWidth: 1))
    }

    private var slidingTabContent: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                runwayTab.frame(width: geometry.size.width)
                feedsTab.frame(width: geometry.size.width)
                pullRequestTab.frame(width: geometry.size.width)
            }
            .offset(x: -CGFloat(selectedTab.index) * geometry.size.width)
            .animation(.spring(response: 0.38, dampingFraction: 0.85), value: selectedTab)
        }
        .clipped()
    }

    // MARK: Runway: my open issues

    private var sortedIssues: [AssignedIssue] {
        issues.issues.sorted { a, b in
            let pa = a.priority ?? "P9", pb = b.priority ?? "P9"
            return pa == pb ? a.updatedAt > b.updatedAt : pa < pb
        }
    }

    private var runwayTab: some View {
        Group {
            if let error = issues.error, !issues.didLoad {
                notice(error, systemImage: "exclamationmark.triangle")
            } else if !issues.didLoad {
                ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if issues.issues.isEmpty {
                notice("No open issues assigned to you.", systemImage: "checkmark.circle")
            } else {
                ScrollViewReader { proxy in
                ScrollView {
                    // Not lazy: a lazy stack skips the layout animation when
                    // a cluster opens, so the blocks below jumped instead of
                    // sliding. There are only a dozen or so clusters.
                    VStack(alignment: .leading, spacing: 6) {
                        Color.clear.frame(height: 0).id("top")
                        ForEach(clusterStacks, id: \.name) { stack in
                            clusterStack(stack)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 4)
                    .padding(.bottom, 16)
                }
                .scrollIndicators(.hidden)
                .onChange(of: cursor) { _, item in scroll(proxy, to: item) }
                .onChange(of: scrollTopTick) { _, _ in
                    withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo("top", anchor: .top) }
                }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: Cluster stacks

    struct ClusterStack {
        let name: String
        let issues: [AssignedIssue]
    }

    /// Issues of one cluster stacked together, in the order of their best
    /// issue (P1 clusters first). The cluster is the label, or the title's
    /// prefix when the label is missing.
    private var clusterStacks: [ClusterStack] {
        var order: [String] = []
        var groups: [String: [AssignedIssue]] = [:]
        for issue in sortedIssues {
            let name = issue.cluster ?? issue.title.components(separatedBy: ":").first?
                .trimmingCharacters(in: .whitespaces) ?? issue.title
            if groups[name] == nil { order.append(name) }
            groups[name, default: []].append(issue)
        }
        // Best priority first (P1 … P5, none last), then by name.
        func best(_ name: String) -> String {
            groups[name]?.compactMap(\.priority).min() ?? "P9"
        }
        return order
            .sorted { a, b in
                let pa = best(a), pb = best(b)
                return pa == pb ? a.localizedCaseInsensitiveCompare(b) == .orderedAscending : pa < pb
            }
            .map { ClusterStack(name: $0, issues: groups[$0] ?? []) }
    }

    private var expandedClusters: Set<String> {
        openClusters ?? Set(expandedClustersRaw.split(separator: "\n").map(String.init))
    }

    /// Switch to a tab; the one already in front, picked again (click or
    /// ⌘⌥1/2/3), refreshes, folds everything and goes back to the top.
    private func selectTab(_ tab: WidgetTab) {
        if selectedTab == tab {
            start()
            scrollTopTick &+= 1
            collapseAll()
        } else {
            withAnimation(.easeInOut(duration: 0.15)) { selectedTab = tab }
        }
    }

    /// Fold everything in every tab: clusters, their issues, the open developer.
    private func collapseAll() {
        withAnimation(.spring(response: 0.42, dampingFraction: 0.82)) {
            openClusters = []
            openIssues = []
            expandedPRAuthor = nil
        }
        expandedClustersRaw = ""
        cursor = nil
    }

    private func toggleCluster(_ name: String) {
        var set = expandedClusters
        let closing = set.contains(name)
        if closing { set.remove(name) } else { set.insert(name) }
        withAnimation(.spring(response: 0.42, dampingFraction: 0.82)) {
            openClusters = set
            // Closing a cluster folds its issues too, so it reopens tidy.
            if closing, let stack = clusterStacks.first(where: { $0.name == name }) {
                openIssues.subtract(stack.issues.map(\.id))
            }
        }
        if closing, case .issue = cursor { cursor = .cluster(name) }
        if closing, case .pull = cursor { cursor = .cluster(name) }
        expandedClustersRaw = set.sorted().joined(separator: "\n")
    }


    /// One block per cluster. Closed, it is a cover with a deck's edges
    /// under it; open, the same card grows its issues as rows underneath.
    /// One view either way, so opening and closing animate in place.
    private func clusterStack(_ stack: ClusterStack) -> some View {
        let isOpen = expandedClusters.contains(stack.name)
        let edges = isOpen ? 0 : min(stack.issues.count - 1, 2)
        return VStack(spacing: 0) {
            ClusterCover(stack: stack, expanded: isOpen, bare: true)
                .background(shownCursor == .cluster(stack.name) ? Color.white.opacity(0.06) : Color.clear)
                .contentShape(Rectangle())
                .onTapGesture { toggleCluster(stack.name) }
                .contextMenu {
                    Button("Copy") { CopyText.put(CopyText.cluster(stack)) }
                }
                .id(NavItem.cluster(stack.name))
            if isOpen {
                // Rows drop in one after another, like a split-flap board
                // turning over, and fold back up together on close.
                ForEach(Array(stack.issues.enumerated()), id: \.element.id) { index, issue in
                    VStack(spacing: 0) {
                        Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1)
                        ClusterIssueRow(
                            issue: issue, cluster: stack.name,
                            open: openIssues.contains(issue.id),
                            cursor: shownCursor,
                            onTap: { toggleIssue(issue) })
                    }
                    .transition(.asymmetric(
                        insertion: .offset(y: -14).combined(with: .opacity)
                            .combined(with: .scale(scale: 0.96, anchor: .top))
                            .animation(.spring(response: 0.38, dampingFraction: 0.78)
                                .delay(0.04 + Double(index) * 0.045)),
                        removal: .opacity.animation(.easeOut(duration: 0.12))
                    ))
                }
            }
        }
        .background(RoundedRectangle(cornerRadius: RunwayCard.radius).fill(RunwayCard.fill()))
        .overlay(
            RoundedRectangle(cornerRadius: RunwayCard.radius)
                .stroke(Color.white.opacity(isOpen ? 0.1 : 0.06), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: RunwayCard.radius))
        .navRing(shownCursor == .cluster(stack.name))
        .background(alignment: .bottom) {
            // One edge per hidden issue (two at most), like a deck.
            ZStack(alignment: .bottom) {
                ForEach((0..<edges).reversed(), id: \.self) { edge in
                    RoundedRectangle(cornerRadius: RunwayCard.radius)
                        .fill(Color(white: 0.06 - Double(edge) * 0.012))
                        .overlay(
                            RoundedRectangle(cornerRadius: RunwayCard.radius)
                                .stroke(Color.white.opacity(0.07 - Double(edge) * 0.02), lineWidth: 1)
                        )
                        // Cut away what sits under the layer above, so the
                        // translucent cards don't show the deck through them.
                        .mask {
                            Rectangle()
                                .overlay(
                                    RoundedRectangle(cornerRadius: RunwayCard.radius)
                                        .padding(.horizontal, -7)
                                        .offset(y: -5)
                                        .blendMode(.destinationOut))
                                .compositingGroup()
                        }
                        .padding(.horizontal, CGFloat(edge + 1) * 7)
                        .offset(y: CGFloat(edge + 1) * 5)
                        .transition(.opacity)
                }
            }
        }
        // The same room under every block, open or closed: a closed deck's
        // edges use it, an open panel leaves it empty.
        .padding(.bottom, isOpen || edges > 0 ? 10 : 4)
    }

    // MARK: Feeds

    private var feedsTab: some View {
        ZStack(alignment: .bottomTrailing) {
            ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    Color.clear.frame(height: 0).id("top")
                    let items = feedItems
                    if items.isEmpty {
                        if !feed.didLoad {
                            ProgressView().controlSize(.small).frame(maxWidth: .infinity).padding(.top, 40)
                        } else if mergesOnly {
                            notice("No merges yet. Merged pull requests will show up here.", systemImage: "arrow.triangle.merge")
                        }
                    }
                    ForEach(items) { event in
                        FeedRow(event: event, time: FeedRow.relative(event.date), isLast: event.id == items.last?.id, repo: event.repo ?? feed.repo)
                            .navRing(shownCursor == .feed(event.id))
                            .id(NavItem.feed(event.id))
                    }
                    if feed.canLoadMore, !items.isEmpty {
                        Button(feed.loadingMore ? "LOADING…" : "LOAD MORE") { Task { await feed.loadMore() } }
                            .buttonStyle(.plain)
                            .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                            .tracking(0.8)
                            .foregroundStyle(Color.white.opacity(0.3))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 64)
            }
            .scrollIndicators(.hidden)
            .onChange(of: cursor) { _, item in scroll(proxy, to: item) }
                .onChange(of: scrollTopTick) { _, _ in
                    withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo("top", anchor: .top) }
                }
            }
            mergeFilterButton
                .padding(8)
        }
    }

    private var mergeFilterButton: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.16)) { mergesOnly.toggle() }
        } label: {
            HStack(spacing: 9) {
                ZStack {
                    RoundedRectangle(cornerRadius: 3.5)
                        .fill(mergesOnly ? Color(red: 0.45, green: 0.82, blue: 0.78) : Color.clear)
                    RoundedRectangle(cornerRadius: 3.5)
                        .stroke(mergesOnly ? Color(red: 0.45, green: 0.82, blue: 0.78) : Color.white.opacity(0.55), lineWidth: 1.5)
                    if mergesOnly {
                        Image(systemName: "checkmark")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(Color.black.opacity(0.75))
                    }
                }
                .frame(width: 14, height: 14)
                Text("Only Merge")
            }
            .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
            .foregroundStyle(Color.white.opacity(0.86))
            .padding(.horizontal, 11)
            .frame(height: 36)
            .background { Color.black.opacity(0.55).background(.ultraThinMaterial) }
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.15), lineWidth: 1))
            .shadow(color: .black.opacity(0.25), radius: 6, y: 2)
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    // MARK: Pulls

    private var pullRequestTab: some View {
        VStack(spacing: 0) {
            prTimeframeSelector
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
            if !pulls.hasSnapshot, let error = pulls.error {
                notice(error, systemImage: "exclamationmark.triangle")
            } else if !pulls.hasSnapshot {
                ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                let developers = pulls.developers(since: prTimeframe.startDate())
                ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        Color.clear.frame(height: 0).id("top")
                        if developers.isEmpty {
                            notice("No pull requests in this timeframe.", systemImage: "arrow.triangle.pull")
                        }
                        ForEach(developers) { developer in
                            pullRequestDeveloperCard(developer)
                                .navRing(shownCursor == .developer(developer.login), radius: 9)
                                .id(NavItem.developer(developer.login))
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
                }
                .scrollIndicators(.hidden)
                .onChange(of: cursor) { _, item in scroll(proxy, to: item) }
                .onChange(of: scrollTopTick) { _, _ in
                    withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo("top", anchor: .top) }
                }
                }
                .id(prTimeframe)
            }
        }
        .onChange(of: prTimeframe) { _, _ in expandedPRAuthor = nil }
    }

    private var prTimeframeSelector: some View {
        HStack(spacing: 2) {
            ForEach(PRTimeframe.allCases) { timeframe in
                Button {
                    prTimeframe = timeframe
                } label: {
                    Text(timeframe.rawValue)
                        .font(.system(size: 9.5, weight: prTimeframe == timeframe ? .semibold : .medium, design: .monospaced))
                        .foregroundStyle(Color.white.opacity(prTimeframe == timeframe ? 0.88 : 0.35))
                        .frame(maxWidth: .infinity)
                        .frame(height: 25)
                        .background(
                            RoundedRectangle(cornerRadius: 5)
                                .fill(prTimeframe == timeframe ? Color.white.opacity(0.09) : .clear)
                        )
                        .contentShape(RoundedRectangle(cornerRadius: 5))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 7).fill(Color.white.opacity(0.035)))
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.white.opacity(0.06), lineWidth: 1))
    }

    private func pullRequestDeveloperCard(_ developer: PullRequestDeveloper) -> some View {
        let expanded = expandedPRAuthor == developer.login
        let username = PersonProfileManager.shared.username(for: developer.login)
        let name = PersonProfileManager.shared.profile(for: developer.login)?.effectiveFullName ?? developer.displayName
        return VStack(spacing: 0) {
            Button {
                withAnimation(.spring(response: 0.30, dampingFraction: 0.88)) {
                    expandedPRAuthor = expanded ? nil : developer.login
                }
            } label: {
                HStack(spacing: 10) {
                    Avatar(login: developer.login, url: developer.avatarURL, size: 30)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(name)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color.white.opacity(0.88))
                            .lineLimit(1)
                        Text("@\(username)")
                            .font(.system(size: 9.5, design: .monospaced))
                            .foregroundStyle(Color.white.opacity(0.32))
                            .lineLimit(1)
                    }
                    Spacer(minLength: 8)
                    if developer.draftCount > 0 { prCount("Draft", developer.draftCount, color: PullRequestList.orange) }
                    if developer.openCount > 0 { prCount("Open", developer.openCount, color: PullRequestList.green) }
                    if developer.mergedCount > 0 { prCount("Merged", developer.mergedCount, color: PullRequestList.purple) }
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8.5, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.30))
                        .rotationEffect(.degrees(expanded ? 180 : 0))
                }
                .padding(11)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if expanded {
                Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1)
                PullRequestList(
                    pullRequests: developer.pullRequests,
                    scope: developer.login.lowercased()
                )
                .padding(11)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(RoundedRectangle(cornerRadius: 9).fill(RunwayCard.fill()))
        .overlay(
            RoundedRectangle(cornerRadius: 9)
                .stroke(Color.white.opacity(expanded ? 0.12 : 0.07), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 9))
    }

    private func prCount(_ label: String, _ count: Int, color: Color) -> some View {
        VStack(alignment: .trailing, spacing: 1) {
            Text(verbatim: "\(count)")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(color.opacity(0.88))
            Text(label)
                .font(.system(size: 7.5, weight: .medium, design: .monospaced))
                .foregroundStyle(Color.white.opacity(0.27))
        }
        .frame(minWidth: 32, alignment: .trailing)
    }

    // MARK: Keyboard

    /// The cursor as drawn: nothing while the mouse is in charge.
    private var shownCursor: NavItem? { keyboardActive ? cursor : nil }

    enum NavItem: Hashable {
        case cluster(String), issue(String), pull(issue: String, number: Int)
        case feed(String), developer(String)
    }

    private var feedItems: [FeedEvent] {
        GitHubFeed.filterNoise(feed.events).filter { event in
            guard mergesOnly else { return true }
            if case .prMerged = event.kind { return true }
            return false
        }
    }

    /// Every row the cursor can land on in the tab in front, top to bottom.
    private var navItems: [NavItem] {
        switch selectedTab {
        case .runway:
            return clusterStacks.flatMap { stack -> [NavItem] in
                var out: [NavItem] = [.cluster(stack.name)]
                guard expandedClusters.contains(stack.name) else { return out }
                for issue in stack.issues {
                    out.append(.issue(issue.id))
                    if openIssues.contains(issue.id) {
                        out += ownedPulls(issue).map { .pull(issue: issue.id, number: $0.number) }
                    }
                }
                return out
            }
        case .feeds:
            return feedItems.map { .feed($0.id) }
        case .pullRequests:
            return pulls.developers(since: prTimeframe.startDate()).map { .developer($0.login) }
        }
    }

    private func installKeys() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.keyDown, .leftMouseDown, .rightMouseDown, .scrollWheel, .mouseMoved]
        ) { event in
            guard event.type == .keyDown else {
                if keyboardActive { keyboardActive = false }
                return event
            }
            guard handleKey(event) else { return event }
            if !keyboardActive { keyboardActive = true }
            return nil
        }
    }

    /// Runway v3's chords plus plain keys, since the panel is all list:
    /// ↑↓ move, ←→ fold and unfold, ↩ acts, Tab and ⌘⌥←→ switch tabs.
    private func handleKey(_ event: NSEvent) -> Bool {
        guard !showRepoPicker else { return false }
        let mods = event.modifierFlags.intersection([.command, .option, .shift, .control])
        let cmdOpt: NSEvent.ModifierFlags = [.command, .option]
        switch (event.keyCode, mods) {
        case (126, []), (126, cmdOpt), (40, []): step(-1)                    // ↑, ⌘⌥↑, k
        case (125, []), (125, cmdOpt), (38, []): step(1)                     // ↓, ⌘⌥↓, j
        case (126, [.shift]), (126, [.command, .option, .shift]): jump(-1)  // ⇧↑, ⌘⌥⇧↑
        case (125, [.shift]), (125, [.command, .option, .shift]): jump(1)   // ⇧↓, ⌘⌥⇧↓
        case (124, []), (37, []): unfold()                                   // →, l
        case (123, []), (4, []): fold()                                      // ←, h
        case (36, []), (76, []), (49, []), (36, cmdOpt): activate()          // ↩, enter, space, ⌘⌥↩
        case (36, [.command]): openCursor()                                  // ⌘↩
        case (8, [.command]): copyCursor()                                   // ⌘C
        case (48, []), (124, cmdOpt), (30, cmdOpt): cycleTab(1)              // tab, ⌘⌥→, ⌘⌥]
        case (48, [.shift]), (123, cmdOpt), (33, cmdOpt): cycleTab(-1)       // ⇧tab, ⌘⌥←, ⌘⌥[
        case (47, cmdOpt): cycleSubtab(1)                                    // ⌘⌥.
        case (43, cmdOpt): cycleSubtab(-1)                                   // ⌘⌥,
        case (18, [.command]), (18, cmdOpt): selectTab(.runway)              // ⌘1, ⌘⌥1
        case (19, [.command]), (19, cmdOpt): selectTab(.feeds)               // ⌘2, ⌘⌥2
        case (20, [.command]), (20, cmdOpt): selectTab(.pullRequests)        // ⌘3, ⌘⌥3
        case (53, []): WidgetAppDelegate.shared?.close()                     // esc
        default: return false
        }
        return true
    }

    /// Step through the options of the tab in front, as in Runway v3:
    /// Pulls walks 24h / 7d / 30d / MTD / YTD, Feeds flips Only Merge.
    private func cycleSubtab(_ delta: Int) {
        switch selectedTab {
        case .pullRequests:
            let all = PRTimeframe.allCases
            guard let index = all.firstIndex(of: prTimeframe) else { return }
            prTimeframe = all[min(max(index + delta, 0), all.count - 1)]
        case .feeds:
            withAnimation(.easeInOut(duration: 0.16)) { mergesOnly = delta > 0 }
        case .runway:
            break
        }
    }

    private func cycleTab(_ delta: Int) {
        let all = WidgetTab.allCases
        let next = (selectedTab.index + delta + all.count) % all.count
        withAnimation(.easeInOut(duration: 0.15)) { selectedTab = all[next] }
    }

    private func step(_ delta: Int) {
        let items = navItems
        guard !items.isEmpty else { return }
        guard let cursor, let index = items.firstIndex(of: cursor) else {
            self.cursor = delta > 0 ? items.first : items.last
            return
        }
        self.cursor = items[min(max(index + delta, 0), items.count - 1)]
    }

    /// Skip to the next cluster or developer; on Feeds, five rows.
    private func jump(_ delta: Int) {
        let items = navItems
        guard selectedTab != .feeds else { return step(delta * 5) }
        let heads = items.filter {
            if case .cluster = $0 { return true }
            if case .developer = $0 { return true }
            return false
        }
        guard !heads.isEmpty else { return }
        let here = cursor.flatMap { items.firstIndex(of: $0) } ?? (delta > 0 ? -1 : items.count)
        let target = delta > 0
            ? heads.first { items.firstIndex(of: $0)! > here }
            : heads.last { items.firstIndex(of: $0)! < here }
        if let target { cursor = target }
    }

    private func issue(withID id: String) -> AssignedIssue? {
        issues.issues.first { $0.id == id }
    }

    private func clusterName(of issue: AssignedIssue) -> String? {
        clusterStacks.first { $0.issues.contains { $0.id == issue.id } }?.name
    }

    private func toggleIssue(_ issue: AssignedIssue) {
        guard !ownedPulls(issue).isEmpty else { return }
        withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
            if openIssues.contains(issue.id) { openIssues.remove(issue.id) } else { openIssues.insert(issue.id) }
        }
    }

    private func toggleDeveloper(_ login: String) {
        withAnimation(.spring(response: 0.30, dampingFraction: 0.88)) {
            expandedPRAuthor = expandedPRAuthor == login ? nil : login
        }
    }

    private func activate() {
        guard let cursor else { return step(1) }
        switch cursor {
        case let .cluster(name): toggleCluster(name)
        case let .issue(id):
            guard let issue = issue(withID: id) else { return }
            if ownedPulls(issue).isEmpty { NSWorkspace.shared.open(issue.url) } else { toggleIssue(issue) }
        case .pull, .feed: openCursor()
        case let .developer(login): toggleDeveloper(login)
        }
    }

    private func unfold() {
        guard let cursor else { return step(1) }
        switch cursor {
        case let .cluster(name):
            if expandedClusters.contains(name) { step(1) } else { toggleCluster(name) }
        case let .issue(id):
            guard let issue = issue(withID: id), !ownedPulls(issue).isEmpty else { return }
            if openIssues.contains(id) { step(1) } else { toggleIssue(issue) }
        case let .developer(login):
            if expandedPRAuthor != login { toggleDeveloper(login) }
        case .pull, .feed: break
        }
    }

    private func fold() {
        guard let cursor else { return }
        switch cursor {
        case let .cluster(name):
            if expandedClusters.contains(name) { toggleCluster(name) }
        case let .issue(id):
            guard let issue = issue(withID: id) else { return }
            if openIssues.contains(id) { toggleIssue(issue) }
            else if let name = clusterName(of: issue) { self.cursor = .cluster(name) }
        case let .pull(id, _):
            self.cursor = .issue(id)
        case let .developer(login):
            if expandedPRAuthor == login { toggleDeveloper(login) }
        case .feed: break
        }
    }

    private func cursorPull() -> LinkedPull? {
        guard case let .pull(id, number) = cursor, let issue = issue(withID: id) else { return nil }
        return ownedPulls(issue).first { $0.number == number }
    }

    private func openCursor() {
        switch cursor {
        case let .issue(id): if let url = issue(withID: id)?.url { NSWorkspace.shared.open(url) }
        case .pull: if let url = cursorPull()?.url { NSWorkspace.shared.open(url) }
        case let .feed(id):
            if let event = feedItems.first(where: { $0.id == id }),
               let url = FeedRow.link(for: event, repo: event.repo ?? feed.repo) { NSWorkspace.shared.open(url) }
        default: activate()
        }
    }

    private func copyCursor() {
        var text: String?
        switch cursor {
        case let .cluster(name): text = clusterStacks.first { $0.name == name }.map { CopyText.cluster($0) }
        case let .issue(id): text = issue(withID: id).map { CopyText.issue($0) }
        case .pull: text = cursorPull().map { CopyText.pull($0) }
        default: break
        }
        guard let text else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func scroll(_ proxy: ScrollViewProxy, to item: NavItem?) {
        guard let item else { return }
        // PR lines have no id of their own; their issue row does.
        let target: NavItem
        if case let .pull(id, _) = item { target = .issue(id) } else { target = item }
        proxy.scrollTo(target)
    }

    // MARK: Helpers

    private func notice(_ message: String, systemImage: String) -> some View {
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

    private static let clockFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "HH:mm"; return f
    }()
    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "EEE HH:mm"; return f
    }()
    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "d MMM"; return f
    }()

    private func clock(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return Self.clockFormatter.string(from: date) }
        if cal.isDateInYesterday(date) { return "Yesterday \(Self.clockFormatter.string(from: date))" }
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: date), to: cal.startOfDay(for: Date())).day ?? 7
        return days < 7 ? Self.dayFormatter.string(from: date) : Self.dateFormatter.string(from: date)
    }

    private func ago(_ date: Date) -> String {
        let s = Int(Date().timeIntervalSince(date))
        if s < 3600 { return "\(max(s / 60, 1))m" }
        if s < 86400 { return "\(s / 3600)h" }
        return "\(s / 86400)d"
    }
}

/// The cover of a cluster's stack: the cluster's name, the repositories its
/// issues live in and the classes they carry. No issue leads it.
private struct ClusterCover: View {
    let stack: WidgetView.ClusterStack
    let expanded: Bool
    /// Inside the open panel: no card of its own, the panel is the card.
    var bare = false
    @State private var hovering = false

    private var repositories: [String] {
        var seen: [String] = []
        for issue in stack.issues where !seen.contains(issue.shortRepository) { seen.append(issue.shortRepository) }
        return seen
    }

    private var classes: [String] {
        Array(Set(stack.issues.compactMap(\.priority))).sorted()
    }

    /// One verdict for the cluster's PRs. Drafts sit out: their CI is not
    /// asking for anything yet. Red beats orange beats green.
    private enum CIVerdict { case failing, running, passing, drafts, unknown }

    private var ciVerdict: CIVerdict {
        let ready = clusterPulls(stack.name).filter { !$0.isDraft }
        if ready.isEmpty { return .drafts }
        let states = ready.map { PullChecks.shared.states[$0.url.absoluteString] }
        if states.contains(where: { $0 == "FAILURE" || $0 == "ERROR" }) { return .failing }
        if states.contains(where: { $0 == "PENDING" || $0 == "EXPECTED" }) { return .running }
        if states.contains(where: { $0 == nil }) { return .unknown }
        return .passing
    }

    private var ciColour: Color {
        switch ciVerdict {
        case .failing: Color(red: 0.95, green: 0.36, blue: 0.32)
        case .running: PullRequestList.orange
        case .passing: PullRequestList.green
        case .drafts: Color.white.opacity(0.35)
        case .unknown: Color.white.opacity(0.85)
        }
    }

    private var ciLabel: String {
        switch ciVerdict {
        case .failing: "CI failing on a PR"
        case .running: "CI running"
        case .passing: "CI green on every PR"
        case .drafts: "All drafts"
        case .unknown: "Checking CI…"
        }
    }

    private var openPullCount: Int { clusterPulls(stack.name).count }

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(stack.name.uppercased())
                    .font(.mono(11.5, .medium))
                    .tracking(0.5)
                    .foregroundStyle(Color(red: 0.945, green: 0.945, blue: 0.933))
                    .lineLimit(1)
                HStack(spacing: 4) {
                    Image(systemName: "book.closed.fill")
                        .font(.system(size: 8))
                    Text(repositories.joined(separator: " + ").uppercased())
                        .font(.mono(8.5))
                        .tracking(1)
                        .lineLimit(1)
                    Text(verbatim: "·").font(.system(size: 8.5))
                    Text("Class")
                        .font(.mono(8.5))
                    if classes.isEmpty {
                        Text("P-").font(.mono(8.5, .semibold))
                    }
                    ForEach(classes, id: \.self) { level in
                        Text(level)
                            .font(.mono(8.5, .semibold))
                            .foregroundStyle(AssignedIssueCard.priorityColor(level))
                    }
                }
                .foregroundStyle(Color(red: 0.541, green: 0.549, blue: 0.565))
            }
            Spacer(minLength: 8)
            let prs = openPullCount
            if prs > 0 {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(verbatim: "\(prs)")
                        .font(.mono(13, .semibold))
                        .foregroundStyle(ciColour)
                        .help(ciLabel)
                    Text(prs == 1 ? "PR" : "PRS")
                        .font(.mono(7.5, .medium))
                        .tracking(1)
                        .foregroundStyle(Color.white.opacity(0.35))
                }
                .frame(width: 34, alignment: .trailing)
            }
            VStack(alignment: .trailing, spacing: 2) {
                Text(verbatim: "\(stack.issues.count)")
                    .font(.mono(13, .semibold))
                    .foregroundStyle(Color.white.opacity(0.85))
                Text(stack.issues.count == 1 ? "ISSUE" : "ISSUES")
                    .font(.mono(7.5, .medium))
                    .tracking(1)
                    .foregroundStyle(Color.white.opacity(0.35))
            }
            .frame(width: 44)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: RunwayCard.radius).fill(bare ? Color.clear : RunwayCard.fill(hovering: hovering)))
        .overlay(RoundedRectangle(cornerRadius: RunwayCard.radius).stroke(bare ? Color.clear : RunwayCard.border(hovering: hovering), lineWidth: 1))
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: hovering)
        .help(expanded ? "Collapse \(stack.name)" : "Show \(stack.issues.count) \(stack.name) issues")
    }
}

/// One issue inside an open cluster panel: what's after the cluster prefix,
/// its number tiles and class, and where it stands.
private struct ClusterIssueRow: View {
    let issue: AssignedIssue
    let cluster: String
    let open: Bool
    let cursor: WidgetView.NavItem?
    let onTap: () -> Void
    @State private var hovering = false

    private var shortTitle: String {
        let prefix = cluster + ":"
        let t = issue.title.hasPrefix(prefix) ? String(issue.title.dropFirst(prefix.count)) : issue.title
        return t.trimmingCharacters(in: .whitespaces)
    }

    /// How wide the number tiles are, so each PR's title lines up under the
    /// issue's title: one tile per digit (size × 1.14) with 2pt between.
    private var flapWidth: CGFloat {
        let digits = CGFloat(String(issue.number).count)
        return digits * 8 * 1.14 + (digits - 1) * 2
    }

    private var ownPulls: [LinkedPull] { ownedPulls(issue) }

    var body: some View {
        let prs = ownPulls
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                FlapNumber(number: issue.number, size: 8)
                Text(shortTitle.uppercased())
                    .font(.mono(10, .medium))
                    .tracking(0.4)
                    .foregroundStyle(Color(red: 0.945, green: 0.945, blue: 0.933))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 6)
                if !prs.isEmpty {
                    Text(verbatim: "\(prs.count) PR")
                        .font(.mono(8.5))
                        .foregroundStyle(Color.white.opacity(0.35))
                }
                if let level = issue.priority {
                    Text(level)
                        .font(.mono(8.5, .semibold))
                        .foregroundStyle(AssignedIssueCard.priorityColor(level))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                cursor == .issue(issue.id) ? Color.white.opacity(0.07)
                    : hovering && !prs.isEmpty ? Color.white.opacity(0.03) : Color.clear)
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
            .onTapGesture(perform: onTap)
            .id(WidgetView.NavItem.issue(issue.id))
            .contextMenu {
                Button("Copy") { CopyText.put(CopyText.issue(issue)) }
                Button("Open issue") { NSWorkspace.shared.open(issue.url) }
                Button("Copy issue name") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString("\(issue.title) #\(issue.number)", forType: .string)
                }
            }

            if open, !prs.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(prs.enumerated()), id: \.element.id) { index, pr in
                        PullLine(pull: pr, numberWidth: flapWidth,
                                 selected: cursor == .pull(issue: issue.id, number: pr.number))
                            .transition(.asymmetric(
                                insertion: .offset(y: -8).combined(with: .opacity)
                                    .animation(.spring(response: 0.32, dampingFraction: 0.82)
                                        .delay(0.03 + Double(index) * 0.04)),
                                removal: .opacity.animation(.easeOut(duration: 0.1))
                            ))
                    }
                }
                .padding(.leading, 12)
                .padding(.trailing, 12)
                .padding(.bottom, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .transition(.opacity)
            }
        }
    }
}

/// One open PR under an issue: number and title on one line.
private struct PullLine: View {
    let pull: LinkedPull
    /// The issue's number tiles' width: the PR number sits in that column so
    /// both titles start at the same x.
    var numberWidth: CGFloat = 50
    var selected = false
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 8) {
            Text(verbatim: "#\(pull.number)")
                .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                .foregroundStyle((pull.isDraft ? PullRequestList.orange : PullRequestList.green).opacity(0.85))
                .lineLimit(1)
                .fixedSize()
                .frame(width: numberWidth, alignment: .trailing)
            Text(pull.branch ?? pull.title)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(Color.white.opacity(hovering ? 0.85 : 0.65))
                .lineLimit(1)
                .truncationMode(.middle)
                .help(pull.branch == nil ? pull.repository : pull.title)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(selected ? Color.white.opacity(0.07) : Color.clear)
                .padding(.horizontal, -6))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture { NSWorkspace.shared.open(pull.url) }
        .contextMenu {
            Button("Copy") { CopyText.put(CopyText.pull(pull)) }
            Button("Open PR") { NSWorkspace.shared.open(pull.url) }
        }
    }
}

/// My open PRs that belong to an issue (see ``AssignedIssues/mentionedPulls``).
@MainActor
func ownedPulls(_ issue: AssignedIssue) -> [LinkedPull] {
    (AssignedIssues.shared.mentionedPulls[issue.id] ?? []).sorted { $0.number > $1.number }
}

/// My open PRs in a cluster, closed issues' PRs included.
@MainActor
func clusterPulls(_ name: String) -> [LinkedPull] {
    AssignedIssues.shared.clusterPulls[name] ?? []
}

extension View {
    /// The keyboard cursor's outline on a card.
    func navRing(_ on: Bool, radius: CGFloat = RunwayCard.radius) -> some View {
        overlay(
            RoundedRectangle(cornerRadius: radius)
                .stroke(Color.white.opacity(on ? 0.5 : 0), lineWidth: 1.2)
                .allowsHitTesting(false))
    }
}

extension Notification.Name {
    static let widgetShown = Notification.Name("RunwayWidgetShown")
}

/// Plain text of a cluster, issue or PR and everything under it, for the
/// Copy menu and ⌘C.
@MainActor
enum CopyText {
    static func put(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    /// "PR #18169"
    static func pull(_ pull: LinkedPull) -> String {
        "PR #\(pull.number)"
    }

    /// "Bookings: Payment system #10387 [P2]"
    static func issue(_ issue: AssignedIssue) -> String {
        "\(issue.title) #\(issue.number)" + (issue.priority.map { " [\($0)]" } ?? "")
    }

    /// "OneSignal Exit (monorepo, 3 issues, 3 PRs)", a blank line, then one
    /// bullet per issue with its PRs.
    static func cluster(_ stack: WidgetView.ClusterStack) -> String {
        let prs = clusterPulls(stack.name).count
        let repos = Array(Set(stack.issues.map(\.shortRepository))).sorted().joined(separator: " + ")
        let count = stack.issues.count
        let header = "\(stack.name) (\(repos), \(count) issue\(count == 1 ? "" : "s"), \(prs) PR\(prs == 1 ? "" : "s"))"
        let lines = stack.issues
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
            .map { item -> String in
                let numbers = ownedPulls(item).map { "#\($0.number)" }
                let tail = numbers.isEmpty ? "" : " (PR\(numbers.count == 1 ? "" : "s") \(numbers.joined(separator: ", ")))"
                return "* " + issue(item) + tail
            }
        return ([header, ""] + lines).joined(separator: "\n")
    }
}
