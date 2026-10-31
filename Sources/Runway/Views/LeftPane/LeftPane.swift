import SwiftUI
import AppKit

/// When an issue list needs a fresh scroll container. AppKit can keep a stale
/// clip origin when the set of cards changes, hiding the first card even though
/// the board model and count include it. An issue that arrives on its own (a
/// refresh, another agent) still rebuilds the container. A card leaving, a
/// reorder, or a card the user dropped in keeps it, with the offset pulled
/// back inside the content, so the list stays where the user was reading.
/// Left pane: a "working now" presence strip on top, then the activity stream.
struct LeftPane: View {
    @Bindable var ws: Workspace
    @Bindable var feed: GitHubFeed
    @Bindable var assignedIssues: AssignedIssues
    @State private var showRepoPicker = false
    @State private var showAllPresence = false
    @State private var pullRequests = PullRequests.shared
    @State private var openIssueScrollAnchor = RunwayScrollAnchor()
    @State private var closedIssueScrollAnchor = RunwayScrollAnchor()
    @State private var feedScrollAnchor = RunwayScrollAnchor()
    @State private var pullScrollAnchor = RunwayScrollAnchor()
    /// there is expected, so it does not rebuild that lane's scroll view.
    @State private var feedSearchVisible = false
    @State private var feedSearchQuery = ""
    @State private var prSearchVisible = false
    @State private var prSearchQuery = ""
    @State private var expandedPRAuthor: String?
    /// Dragging a flight to a new place, v2's way: one gesture, live frames.
    @State private var flightDrag = FlightDrag()
    /// Stacks fanned out, by their bottom PR.
    @FocusState private var focusedSearchTab: FeedTab?
    @AppStorage(SettingsKey.fireThreshold) private var fireThreshold = 5
    @AppStorage(SettingsKey.brandHeaderStyle) private var brandHeaderStyle = "text"
    @AppStorage(SettingsKey.brandTitle) private var brandTitle = Self.defaultBrandTitle

    /// What the left pane calls itself before anyone renames it in Settings.
    static let defaultBrandTitle = "Runway V3"

    @AppStorage(SettingsKey.brandLogoFilename) private var brandLogoFilename = ""

    private static let taglines = [
        "WHAT HAS BEEN HAPPENING",
        "LATELY ON THE WIRE",
        "WHAT HAS BEEN COOKING",
        "RECENTLY ON THE RADAR",
        "THINGS CURRENTLY IN MOTION",
        "WHAT IS MOVING NOW",
        "LIVE FROM THE REPO",
        "FRESH OFF THE WIRE",
        "THE LATEST RUNDOWN HERE",
        "WHAT IS IN THE AIR",
        "SIGNAL ON THE WIRE",
        "WHAT IS ON THE RADAR",
        "UP TO THE MINUTE STATUS",
        "ACTIVE RADAR ON THE GO",
        "FEEDS RUNNING IN MOTION",
        "DEVELOPMENTS ON THE GROUND",
        "LATEST FROM THE ENGINE",
        "CATCH UP ON RECENT GOINGS",
        "WHILE YOU WERE AWAY INBOX",
        "STREAMING LIVE ON THE RADAR",
    ]
    @State private var taglineIndex = Int.random(in: 0..<20)
    @State private var displayedTagline = ""
    @State private var taglineOpacity: Double = 1.0
    @State private var isTyping = false
    @State private var lastEventCount = 0
    @State private var taglineTask: Task<Void, Never>?
    @State private var lastTaglineChange = Date.distantPast
    @AppStorage(SettingsKey.taglineEnabled) private var taglineEnabled = true

    var body: some View {
        ZStack(alignment: .topLeading) {
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
                } else {
                    if !feed.presence.isEmpty {
                        presenceStrip
                        feedDivider
                    } else if feed.didLoad {
                        emptyOfficeNotice
                        feedDivider
                    }
                    subHeader
                    slidingTabContent
                }
            }
            .clipped()

        }
        // Coming back to the window refreshes both sources, not only the tab
        // in front.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            syncAllSources(tick: 15)
        }
        // One clock for both sources, so neither shows minutes-old data the
        // moment you switch to it.
        .task(id: feed.repo) {
            while !Task.isCancelled {
                let interval = feed.pollInterval
                if NSApp.isActive { syncAllSources(tick: TimeInterval(interval)) }
                do {
                    try await Task.sleep(nanoseconds: interval * 1_000_000_000)
                } catch {
                    return
                }
            }
        }
        .onChange(of: ws.tabResetRequestID) { _, _ in
            resetActiveTab()
        }
        .onChange(of: ws.sourceRefreshRequestID) { _, _ in
            refreshSource(for: ws.sourceRefreshTab, minimumAge: 0)
        }
        .onChange(of: ws.selectedTab) { previousTab, tab in
            closeEmptySearch(for: previousTab)
            focusedSearchTab = nil
            refreshSource(for: tab, minimumAge: 15)
        }
        .onChange(of: ws.findRequestID) { _, _ in
            toggleSearch(for: ws.selectedTab)
        }
        .onChange(of: ws.repoPickerRequestID) { _, _ in
            showRepoPicker = true
            feed.fetchRepoList()
        }
        .task(id: emptySearchIsOpen(for: .feeds)) {
            await closeSearchAfterIdle(for: .feeds)
        }
        .task(id: emptySearchIsOpen(for: .pullRequests)) {
            await closeSearchAfterIdle(for: .pullRequests)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        // Black, like the other two panes: the cards are the only surface,
        // so no seam shows where one pane meets the next.
        .background(Color.black)
    }

    /// Only the floating card reads the pointer position. Reading it here
    /// would re-run this whole body, every lane and all its cards, on each
    /// mouse move, which made dragging crawl on boards with hundreds of issues.
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
        VStack(spacing: 0) {
            if !ws.isFullScreen {
                WindowDragRegion()
                    .frame(height: 42)
            }

            HStack(alignment: .center, spacing: 8) {
                brandingTitle
                    .layoutPriority(1)
                if ws.isFullScreen {
                    Spacer(minLength: 8)
                } else {
                    WindowDragRegion()
                        .frame(maxWidth: .infinity)
                        .frame(height: 40)
                }
                repoButton
            }
            .padding(.horizontal, 16)
            .padding(.top, ws.isFullScreen ? 18 : 8)
            .padding(.bottom, 22)
        }
    }

    @ViewBuilder
    private var brandingTitle: some View {
        if brandHeaderStyle == "image",
           let image = BrandingManager.image(named: brandLogoFilename) {
            let imageSize = image.size
            let aspectRatio = imageSize.height > 0 ? imageSize.width / imageSize.height : 1
            let height: CGFloat = 34
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .frame(width: min(180, height * aspectRatio), height: height)
                .accessibilityLabel(Self.defaultBrandTitle)
        } else {
            Text(resolvedBrandTitle)
                .font(.system(size: 27, weight: .bold))
                .foregroundStyle(Color.white.opacity(0.95))
                .lineLimit(1)
        }
    }

    private var resolvedBrandTitle: String {
        let title = brandTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? Self.defaultBrandTitle : title
    }

    /// The clone's folder name, which is also its Focus agents' name prefix.
    private var repoButtonTitle: String {
        if let path = feed.localPath(for: feed.repo) {
            return CloneName.name(ofCheckout: path)
        }
        return feed.repo.split(separator: "/").last.map(String.init) ?? feed.repo
    }

    private var repoChoices: [RepoPicker.Choice] {
        feed.availableRepos.flatMap { repository in
            feed.checkouts(for: repository).map { path in
                RepoPicker.Choice(repository: repository, path: path)
            }
        }
    }

    /// Rounded-rectangle repo selector with a repo glyph; opens a searchable picker.
    private var repoButton: some View {
        Button {
            showRepoPicker.toggle()
            if showRepoPicker { feed.fetchRepoList(force: true) }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "book.closed.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.5))
                Text(repoButtonTitle)
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
        .pointerCursor()
        .popover(isPresented: $showRepoPicker, arrowEdge: .bottom) {
            RepoPicker(repos: repoChoices, current: feed.localPath(for: feed.repo)) { picked in
                feed.selectCheckout(picked.path, of: picked.repository)
                showRepoPicker = false
            }
        }
        .task(id: showRepoPicker) {
            guard showRepoPicker else { return }
            while !Task.isCancelled {
                feed.fetchRepoList(force: true)
                do {
                    try await Task.sleep(for: .seconds(3))
                } catch {
                    return
                }
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
                .pointerCursor()
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
            .padding(.horizontal, 7)
            .padding(.vertical, 10)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }

    // MARK: Activity stream
    @State private var pulled = false

    private var subHeader: some View {
        HStack(alignment: .center, spacing: 8) {
            Text(subHeaderText)
                .opacity(ws.selectedTab == .feeds ? taglineOpacity : 1)
            Spacer(minLength: 8)
            feedTabs
        }
        .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
        .foregroundStyle(Color.white.opacity(0.3))
        .tracking(0.8)
        .lineLimit(1)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .onAppear {
            if displayedTagline.isEmpty {
                displayedTagline = Self.taglines[taglineIndex]
                lastEventCount = feed.events.count
            }
        }
        .onChange(of: feed.events.count) { old, new in
            guard taglineEnabled else { return }
            guard ws.selectedTab == .feeds, new > old, !isTyping else { return }
            // A returning-from-idle batch arrives as several inserts in a row.
            // Retyping the line for each one is pure churn on the main thread at
            // the exact moment the list is already animating.
            guard Date().timeIntervalSince(lastTaglineChange) > Self.taglineMinimumInterval else { return }
            rotateTagline()
        }
        .onDisappear { taglineTask?.cancel() }
    }

    private var subHeaderText: String {
        switch ws.selectedTab {
        case .runway: "ON TODAY'S MISSIONS"
        case .feeds: displayedTagline
        case .pullRequests: "PULL REQUESTS BY DEV"
        }
    }

    private var selectedTabIndex: Int {
        switch ws.selectedTab {
        case .runway: 0
        case .feeds: 1
        case .pullRequests: 2
        }
    }

    private var slidingTabContent: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                runwayTab
                    .frame(width: geometry.size.width)
                feedsTab
                    .frame(width: geometry.size.width)
                pullRequestTab
                    .frame(width: geometry.size.width)
            }
            .offset(x: -CGFloat(selectedTabIndex) * geometry.size.width)
            .animation(
                .spring(response: 0.38, dampingFraction: 0.85),
                value: ws.selectedTab
            )
        }
        .clipped()
    }

    /// The issues assigned to you, Open or Closed.
    private var runwayTab: some View {
        VStack(alignment: .leading, spacing: 0) {
            runwayIssueTabs
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 16)
                .padding(.bottom, 10)

            if assignedIssues.loading && !assignedIssues.hasSnapshot {
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = assignedIssues.error, !assignedIssues.hasSnapshot {
                feedNotice(error, systemImage: "exclamationmark.triangle")
            } else {
                GeometryReader { geo in
                    HStack(spacing: 0) {
                        issueList(assignedIssues.open, lane: .open)
                            .frame(width: geo.size.width)
                        issueList(assignedIssues.closed, lane: .closed)
                            .frame(width: geo.size.width)
                    }
                    .offset(x: ws.runwayIssueTab == .open ? 0 : -geo.size.width)
                    .animation(
                        .spring(response: 0.38, dampingFraction: 0.85),
                        value: ws.runwayIssueTab
                    )
                }
                .frame(maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
                .clipped()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var runwayIssueTabs: some View {
        HStack(spacing: 0) {
            ForEach(RunwayIssueTab.allCases) { tab in
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { ws.runwayIssueTab = tab }
                } label: {
                    HStack(spacing: 5) {
                        Text(tab.rawValue)
                        Text("\(tab == .open ? assignedIssues.open.count : assignedIssues.closed.count)")
                            .foregroundStyle(Color.white.opacity(0.35))
                    }
                    .font(.system(size: 10.5, weight: ws.runwayIssueTab == tab ? .semibold : .medium))
                    .foregroundStyle(
                        ws.runwayIssueTab == tab
                            ? Color.white.opacity(0.9)
                            : Color.white.opacity(0.4)
                    )
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .frame(maxWidth: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(ws.runwayIssueTab == tab ? Color.white.opacity(0.1) : Color.clear)
                    )
                    .contentShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .pointerCursor()
            }
        }
        .frame(maxWidth: .infinity)
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.04)))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.06), lineWidth: 1))
    }

    /// One card. In the open lane it can be dragged to a new place.
    @ViewBuilder
    private func issueCard(
        _ issue: AssignedIssue,
        lane: RunwayIssueTab,
        among numbers: [Int]
    ) -> some View {
        AssignedIssueCard(
            issue: issue,
            repository: issueRepositoryName,
            boardKey: assignedIssues.repository ?? "",
            isFlying: ws.flightNumber == issue.number,
            onSetClosed: { closed in
                Task { await assignedIssues.setClosed(closed, issue: issue.number) }
            }
        )
        .opacity(flightDrag.issue == issue.number ? 0 : 1)
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.18)) { ws.flightNumber = issue.number }
        }
        .modifier(
            DraggableFlight(
                enabled: lane == .open,
                issue: issue.number,
                lane: numbers,
                repository: assignedIssues.repository ?? "",
                drag: flightDrag
            )
        )
    }

    private func issueList(_ issues: [AssignedIssue], lane: RunwayIssueTab) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 8) {
                ForEach(issues) { issue in
                    issueCard(issue, lane: lane, among: issues.map(\.number))
                }
            }
            .overlay(alignment: .topLeading) {
                if let number = flightDrag.issue,
                   let issue = issues.first(where: { $0.number == number }) {
                    FlightDragCard(
                        drag: flightDrag,
                        issue: issue,
                        repository: issueRepositoryName,
                        boardKey: assignedIssues.repository ?? ""
                    )
                }
            }
            .coordinateSpace(name: FlightDrag.space)
            // Where the list sits in the window, so the drag can read the
            // real mouse position in the list's own terms.
            .onGeometryChange(for: CGRect.self) { proxy in
                proxy.frame(in: .global)
            } action: { frame in
                flightDrag.reportSpace(frame)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
            .scrollAnchor(lane == .open ? openIssueScrollAnchor : closedIssueScrollAnchor)
        }
        .contentMargins(.vertical, 0, for: .scrollContent)
        .scrollIndicators(.hidden)
        .overlay {
            if issues.isEmpty {
                placeholderCard(
                    icon: lane == .open ? "tray" : "checkmark.circle",
                    title: lane == .open ? "No open issues" : "No closed issues",
                    subtitle: "Issues assigned to you in this repository appear here."
                )
                .padding(.horizontal, 16)
            }
        }
    }

    private var issueRepositoryName: String {
        feed.repo.split(separator: "/").last.map(String.init) ?? feed.repo
    }

    private var feedsTab: some View {
        VStack(spacing: 0) {
            if feedSearchVisible {
                searchField(
                    placeholder: "Search feeds",
                    text: $feedSearchQuery,
                    tab: .feeds
                )
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            ZStack(alignment: .bottomTrailing) {
                feedScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        let sourceItems = GitHubFeed.filterNoise(feed.events).filter { event in
                            guard ws.feedFilter.showsMergesOnly else { return true }
                            if case .prMerged = event.kind { return true }
                            return false
                        }
                        let items = filteredFeedEvents(
                            sourceItems,
                            query: feedSearchQuery,
                            isSearching: feedSearchVisible
                        )
                        if items.isEmpty {
                            if feedSearchVisible,
                               !feedSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                searchEmptyPlaceholder("No matching feed activity")
                            } else if ws.feedFilter.showsMergesOnly {
                                mergeEmptyPlaceholder
                            } else {
                                emptyTabPlaceholder(for: .feeds)
                            }
                        } else {
                            ForEach(items) { event in
                                FeedRow(
                                    event: event,
                                    time: clock(event.date),
                                    isLast: event.id == items.last?.id,
                                    repo: feed.repo
                                )
                                .transition(.move(edge: .top).combined(with: .opacity))
                            }
                        }
                        loadMoreFooter
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 64)
                }
                mergeFilterButton
                    .padding(8)
            }
        }
    }

    private var pullRequestTab: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                if prSearchVisible {
                    searchField(
                        placeholder: "Search developers or pull requests",
                        text: $prSearchQuery,
                        tab: .pullRequests
                    )
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
                prTimeframeSelector
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)

            if pullRequests.catchingUpOnHistory {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small).scaleEffect(0.55)
                        .frame(width: 10, height: 10)
                    Text("NEWEST \(PullRequests.firstPaintCount) · STILL READING THIS REPOSITORY'S HISTORY")
                        .font(.system(size: 7.5, weight: .medium, design: .monospaced))
                        .foregroundStyle(Color.white.opacity(0.28))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            }
            if pullRequests.loading && !pullRequests.hasSnapshot {
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = pullRequests.error, !pullRequests.hasSnapshot {
                feedNotice(error, systemImage: "exclamationmark.triangle")
            } else {
                let developers = filteredPRDevelopers
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        if developers.isEmpty {
                            placeholderCard(
                                icon: prSearchQuery.isEmpty ? "arrow.triangle.pull" : "magnifyingglass",
                                title: prSearchQuery.isEmpty
                                    ? "No pull requests in this timeframe"
                                    : "No matching pull requests",
                                subtitle: prSearchQuery.isEmpty
                                    ? "Try a wider timeframe."
                                    : "Try a different search."
                            )
                        } else {
                            ForEach(developers) { developer in
                                pullRequestDeveloperCard(developer)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
                    .scrollAnchor(pullScrollAnchor)
                }
                .contentMargins(.top, 0, for: .scrollContent)
                .scrollIndicators(.hidden)
                .id(ws.prTimeframe)
            }
        }
        .task(id: feed.repo) {
            expandedPRAuthor = nil
            pullRequests.restore(repository: feed.repo)
            await pullRequests.revalidate(repository: feed.repo, minimumAge: 30)
        }
        // Changing the window resets paging: the counts and the expanded
        // developer belong to the window that produced them.
        .onChange(of: ws.prTimeframe) { _, _ in
            expandedPRAuthor = nil
        }
    }

    private var prTimeframeSelector: some View {
        HStack(spacing: 2) {
            ForEach(PRTimeframe.allCases) { timeframe in
                Button {
                    guard ws.prTimeframe != timeframe else { return }
                    ws.prTimeframe = timeframe
                } label: {
                    Text(timeframe.rawValue)
                        .font(.system(
                            size: 9.5,
                            weight: ws.prTimeframe == timeframe ? .semibold : .medium,
                            design: .monospaced
                        ))
                        .foregroundStyle(
                            Color.white.opacity(ws.prTimeframe == timeframe ? 0.88 : 0.35)
                        )
                        .frame(maxWidth: .infinity)
                        .frame(height: 25)
                        .background(
                            RoundedRectangle(cornerRadius: 5)
                                .fill(ws.prTimeframe == timeframe ? Color.white.opacity(0.09) : .clear)
                        )
                        .contentShape(RoundedRectangle(cornerRadius: 5))
                }
                .buttonStyle(.plain)
                .pointerCursor()
            }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 7).fill(Color.white.opacity(0.035)))
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.white.opacity(0.06), lineWidth: 1))
    }

    private var filteredPRDevelopers: [PullRequestDeveloper] {
        let developers = pullRequests.developers(since: ws.prTimeframe.startDate())
        let query = prSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard prSearchVisible, !query.isEmpty else { return developers }

        return developers.compactMap { developer in
            let developerText = "\(developer.login) \(pullRequestDeveloperUsername(developer)) \(pullRequestDeveloperDisplayName(developer))"
            if SearchText.contains(developerText, query) {
                return developer
            }
            let matches = developer.pullRequests.filter { pullRequest in
                SearchText.contains(
                    "\(GitHubNumber.reference(pullRequest.number)) \(pullRequest.title) \(pullRequest.headRefName) \(pullRequest.baseRefName)",
                    query
                )
            }
            guard !matches.isEmpty else { return nil }
            return PullRequestDeveloper(
                login: developer.login,
                name: developer.name,
                pullRequests: matches
            )
        }
        .sorted { lhs, rhs in
            PullRequestDeveloper.ranksAbove(
                lhs, rhs, displayName: pullRequestDeveloperDisplayName
            )
        }
    }

    private func pullRequestDeveloperUsername(_ developer: PullRequestDeveloper) -> String {
        PersonProfileManager.shared.username(for: developer.login)
    }

    private func pullRequestDeveloperDisplayName(_ developer: PullRequestDeveloper) -> String {
        PersonProfileManager.shared.profile(for: developer.login)?.effectiveFullName
            ?? developer.displayName
    }

    private func pullRequestDeveloperCard(_ developer: PullRequestDeveloper) -> some View {
        let expanded = expandedPRAuthor == developer.login
        return VStack(spacing: 0) {
            Button {
                withAnimation(.spring(response: 0.30, dampingFraction: 0.88)) {
                    expandedPRAuthor = expanded ? nil : developer.login
                }
            } label: {
                HStack(spacing: 10) {
                    Avatar(login: developer.login, url: developer.avatarURL, size: 30)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(pullRequestDeveloperDisplayName(developer))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color.white.opacity(0.88))
                            .lineLimit(1)
                        Text("@\(pullRequestDeveloperUsername(developer))")
                            .font(.system(size: 9.5, design: .monospaced))
                            .foregroundStyle(Color.white.opacity(0.32))
                            .lineLimit(1)
                    }
                    Spacer(minLength: 8)
                    if developer.draftCount > 0 {
                        prCount("Draft", developer.draftCount, color: PullRequestList.orange)
                    }
                    if developer.openCount > 0 {
                        prCount("Open", developer.openCount, color: PullRequestList.green)
                    }
                    if developer.mergedCount > 0 {
                        prCount("Merged", developer.mergedCount, color: PullRequestList.purple)
                    }
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8.5, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.30))
                        .rotationEffect(.degrees(expanded ? 180 : 0))
                }
                .padding(11)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .pointerCursor()

            if expanded {
                Rectangle()
                    .fill(Color.white.opacity(0.06))
                    .frame(height: 1)
                // A stack sits in the section of its bottom PR, the one next
                // to merge, even when the PRs above it are drafts.
                PullRequestList(
                    pullRequests: developer.pullRequests,
                    scope: developer.login.lowercased()
                )
                .padding(11)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(RoundedRectangle(cornerRadius: 9).fill(Color(white: 0.075)))
        .overlay(
            RoundedRectangle(cornerRadius: 9)
                .stroke(Color.white.opacity(expanded ? 0.12 : 0.07), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 9))
    }

    private func prCount(_ label: String, _ count: Int, color: Color) -> some View {
        VStack(alignment: .trailing, spacing: 1) {
            Text("\(count)")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(color.opacity(0.88))
            Text(label)
                .font(.system(size: 7.5, weight: .medium, design: .monospaced))
                .foregroundStyle(Color.white.opacity(0.27))
        }
        .frame(minWidth: 32, alignment: .trailing)
    }

    /// The same three moves an issue card offers, from the PR side: its issue
    /// is the number its branch ends with, by the branch convention.
    private func searchField(
        placeholder: String,
        text: Binding<String>,
        tab: FeedTab
    ) -> some View {
        RunwaySearchField(
            placeholder: placeholder,
            query: text,
            tab: tab,
            focus: $focusedSearchTab
        )
    }

    private func toggleSearch(for tab: FeedTab) {
        var willShow = false
        withAnimation(.easeInOut(duration: 0.16)) {
            switch tab {
            case .runway:
                return
            case .feeds:
                feedSearchVisible.toggle()
                willShow = feedSearchVisible
                if !willShow { feedSearchQuery = "" }
            case .pullRequests:
                prSearchVisible.toggle()
                willShow = prSearchVisible
                if !willShow { prSearchQuery = "" }
            }
        }

        if willShow {
            DispatchQueue.main.async {
                focusedSearchTab = tab
            }
        } else {
            focusedSearchTab = nil
        }
    }

    private func emptySearchIsOpen(for tab: FeedTab) -> Bool {
        switch tab {
        case .runway:
            return false
        case .feeds:
            return feedSearchVisible
                && feedSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .pullRequests:
            return prSearchVisible
                && prSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    private func closeEmptySearch(for tab: FeedTab) {
        guard emptySearchIsOpen(for: tab) else { return }
        closeSearch(for: tab)
    }

    private func closeSearchAfterIdle(for tab: FeedTab) async {
        guard emptySearchIsOpen(for: tab) else { return }
        do {
            try await Task.sleep(nanoseconds: 60_000_000_000)
        } catch {
            return
        }
        guard !Task.isCancelled, emptySearchIsOpen(for: tab) else { return }
        closeSearch(for: tab)
    }

    private func closeSearch(for tab: FeedTab) {
        withAnimation(.easeInOut(duration: 0.16)) {
            switch tab {
            case .runway:
                return
            case .feeds:
                feedSearchVisible = false
                feedSearchQuery = ""
            case .pullRequests:
                prSearchVisible = false
                prSearchQuery = ""
            }
        }
        if focusedSearchTab == tab {
            focusedSearchTab = nil
        }
    }

    private func filteredFeedEvents(
        _ events: [FeedEvent],
        query: String,
        isSearching: Bool
    ) -> [FeedEvent] {
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isSearching, !normalized.isEmpty else { return events }
        return events.filter {
            SearchText.contains(feedEventSearchText($0), normalized)
        }
    }

    private func feedEventSearchText(_ event: FeedEvent) -> String {
        let actor = "\(event.actor) \(PersonProfileManager.shared.username(for: event.actor)) \(PersonProfileManager.shared.fullName(for: event.actor))"
        let detail: String
        switch event.kind {
        case let .push(branch, count, commits):
            detail = "push pushed \(branch) \(count.map(String.init) ?? "") "
                + commits.map { "\($0.sha) \($0.message)" }.joined(separator: " ")
        case let .prOpened(number, title, branch):
            detail = "pull request pr opened \(GitHubNumber.reference(number)) \(title) \(branch)"
        case let .prMerged(number, title, base, branch, additions, deletions, commits, _):
            detail = "pull request pr merged merge \(GitHubNumber.reference(number)) \(title) \(base) \(branch) "
                + "\(additions.map(String.init) ?? "") \(deletions.map(String.init) ?? "") "
                + "\(commits.map(String.init) ?? "")"
        case let .branchCreated(name):
            detail = "branch created \(name)"
        case let .branchDeleted(name):
            detail = "branch deleted \(name)"
        case let .review(number, title, state):
            detail = "review reviewed pull request pr \(GitHubNumber.reference(number)) \(title) \(state)"
        case let .issueOpened(number, title):
            detail = "issue opened open \(GitHubNumber.reference(number)) \(title)"
        case let .issueClosed(number, title):
            detail = "issue closed close \(GitHubNumber.reference(number)) \(title)"
        }
        return "\(actor) \(detail)"
    }

    private func syncAllSources(tick: TimeInterval) {
        let ages = RepositorySyncCadence.ages(for: ws.selectedTab, tick: tick)
        Task { await feed.refresh(minimumAge: ages.feed) }
        Task { await assignedIssues.revalidate(repository: feed.repo, minimumAge: ages.issues) }
        Task {
            await pullRequests.revalidate(
                repository: feed.repo,
                minimumAge: ages.pulls
            )
        }
    }

    private func refreshSource(for tab: FeedTab, minimumAge: TimeInterval) {
        switch tab {
        case .runway:
            Task { await assignedIssues.revalidate(repository: feed.repo, minimumAge: minimumAge) }
        case .feeds:
            Task { await feed.refresh(minimumAge: minimumAge) }
        case .pullRequests:
            Task {
                await pullRequests.revalidate(
                    repository: feed.repo,
                    minimumAge: minimumAge
                )
            }
        }
    }

    /// Picking the tab already showing: back to the top of its list, and refetch
    /// straight away rather than waiting for the next tick.
    private func resetActiveTab() {
        scrollAnchor(for: ws.selectedTab).scrollToTop()
        refreshSource(for: ws.selectedTab, minimumAge: 0)
        // A refresh that turns up nothing new still has to look like one. The
        // tagline retypes on the tap itself rather than on an event arriving,
        // and skips the burst guard because the user asked for it by hand.
        if ws.selectedTab == .feeds, taglineEnabled { rotateTagline() }
    }

    private func scrollAnchor(for tab: FeedTab) -> RunwayScrollAnchor {
        switch tab {
        case .runway: ws.runwayIssueTab == .open ? openIssueScrollAnchor : closedIssueScrollAnchor
        case .feeds: feedScrollAnchor
        case .pullRequests: pullScrollAnchor
        }
    }

    @ViewBuilder private func feedScrollView<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        ScrollView {
            VStack(spacing: 0) {
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

                content()
            }
            .scrollAnchor(feedScrollAnchor)
        }
        .contentMargins(.top, 0, for: .scrollContent)
        .scrollIndicators(.hidden)
        .coordinateSpace(name: "feed")
    }

    private var loadMoreFooter: some View {
        Group {
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

    // MARK: Empty tab placeholder
    @ViewBuilder private func emptyTabPlaceholder(for tab: FeedTab) -> some View {
        switch tab {
        case .runway:
            EmptyView()
        case .feeds:
            placeholderCard(icon: "tray", title: "No activity yet",
                            subtitle: "Events from your team will appear here as they happen.")
        case .pullRequests:
            EmptyView()
        }
    }

    private var mergeEmptyPlaceholder: some View {
        placeholderCard(
            icon: "arrow.triangle.merge",
            title: "No merges yet",
            subtitle: "Merged pull requests will show up here."
        )
    }

    private func searchEmptyPlaceholder(_ title: String) -> some View {
        placeholderCard(
            icon: "magnifyingglass",
            title: title,
            subtitle: "Try a different search."
        )
    }

    private var mergeFilterButton: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.16)) {
                ws.feedFilter = ws.feedFilter.showsMergesOnly ? .all : .merges
            }
        } label: {
            HStack(spacing: 9) {
                ZStack {
                    RoundedRectangle(cornerRadius: 3.5)
                        .fill(
                            ws.feedFilter.showsMergesOnly
                                ? Color(red: 0.45, green: 0.82, blue: 0.78)
                                : Color.clear
                        )
                    RoundedRectangle(cornerRadius: 3.5)
                        .stroke(
                            ws.feedFilter.showsMergesOnly
                                ? Color(red: 0.45, green: 0.82, blue: 0.78)
                                : Color.white.opacity(0.55),
                            lineWidth: 1.5
                        )
                    if ws.feedFilter.showsMergesOnly {
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
            .background {
                Color.black.opacity(0.55)
                    .background(.ultraThinMaterial)
            }
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.white.opacity(0.15), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.25), radius: 6, y: 2)
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .pointerCursor()
    }

    private func placeholderCard(icon: String, title: String, subtitle: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 24, weight: .light))
                .foregroundStyle(Color.white.opacity(0.15))
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.4))
            Text(subtitle)
                .font(.system(size: 11.5))
                .foregroundStyle(Color.white.opacity(0.25))
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 20)
        .padding(.vertical, 36)
    }

    private var feedTabs: some View {
        HStack(spacing: 0) {
            ForEach(FeedTab.allCases, id: \.rawValue) { tab in
                Button {
                    // Already here: treat the second tap as "take me back to the
                    // top and get me the latest".
                    if ws.selectedTab == tab {
                        ws.requestTabReset()
                    } else {
                        withAnimation(.easeInOut(duration: 0.15)) { ws.selectedTab = tab }
                    }
                } label: {
                    Text(tab.rawValue)
                        .font(.system(size: 10, weight: ws.selectedTab == tab ? .semibold : .medium, design: .monospaced))
                        .foregroundStyle(ws.selectedTab == tab ? Color.white.opacity(0.9) : Color.white.opacity(0.35))
                        .fixedSize(horizontal: true, vertical: false)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 5)
                                .fill(ws.selectedTab == tab ? Color.white.opacity(0.1) : Color.clear)
                        )
                        .contentShape(RoundedRectangle(cornerRadius: 5))
                }
                .buttonStyle(.plain)
                .pointerCursor()
            }
        }
        .fixedSize(horizontal: true, vertical: false)
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 7).fill(Color.white.opacity(0.04)))
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.white.opacity(0.06), lineWidth: 1))
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
                HStack(alignment: .center, spacing: 8) {
                    Text(subHeaderText)
                        .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Color.white.opacity(0.3))
                        .tracking(0.8)
                        .lineLimit(1)
                        .opacity(ws.selectedTab == .feeds ? taglineOpacity : 1)
                    Spacer(minLength: 8)
                    feedTabs
                }
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



    /// Relative duration, used for "idle 3h" in the presence strip.
    private func ago(_ date: Date) -> String {
        let s = Int(Date().timeIntervalSince(date))
        if s < 3600 { return "\(max(s / 60, 1))m" }
        if s < 86400 { return "\(s / 3600)h" }
        return "\(s / 86400)d"
    }

    // MARK: Tagline rotation

    /// Shortest gap between two tagline changes. One rotation per burst of new
    /// events, not one per event.
    private static let taglineMinimumInterval: TimeInterval = 6

    /// Fade the line out, then type the next one in. A single cancellable task,
    /// so a second rotation can never interleave with one still typing.
    private func rotateTagline() {
        taglineTask?.cancel()
        isTyping = true
        lastTaglineChange = Date()
        withAnimation(.easeOut(duration: 0.25)) { taglineOpacity = 0 }
        taglineTask = Task { @MainActor in
            defer { isTyping = false }
            do {
                try await Task.sleep(nanoseconds: 300_000_000)
                taglineIndex = (taglineIndex + 1) % Self.taglines.count
                let target = Self.taglines[taglineIndex]
                displayedTagline = ""
                taglineOpacity = 1.0
                for character in target {
                    try await Task.sleep(nanoseconds: 25_000_000)
                    displayedTagline.append(character)
                }
            } catch {
                return
            }
        }
    }
}

/// One entry in a Pulls section: a lone PR, or a stack of PRs each based on
/// the branch of the one below, listed top first.
enum PRStackItem: Identifiable {
    case single(RepositoryPullRequest)
    case stack([RepositoryPullRequest])

    var id: Int { bottom.number }

    var pullRequests: [RepositoryPullRequest] {
        switch self {
        case .single(let pullRequest): [pullRequest]
        case .stack(let stack): stack
        }
    }

    /// The PR nearest the target branch, next to merge.
    var bottom: RepositoryPullRequest {
        switch self {
        case .single(let pullRequest): pullRequest
        case .stack(let stack): stack[stack.count - 1]
        }
    }

    /// Groups PRs whose base is another of these PRs' head. Each stack takes
    /// the place of its first PR in the list.
    static func items(_ pullRequests: [RepositoryPullRequest]) -> [PRStackItem] {
        let byHead = Dictionary(pullRequests.map { ($0.headRefName, $0) }, uniquingKeysWith: { first, _ in first })
        var children: [String: [RepositoryPullRequest]] = [:]
        for pullRequest in pullRequests where byHead[pullRequest.baseRefName] != nil {
            children[pullRequest.baseRefName, default: []].append(pullRequest)
        }
        var items: [PRStackItem] = []
        var placed: Set<Int> = []
        for pullRequest in pullRequests where !placed.contains(pullRequest.number) {
            var root = pullRequest
            var seen: Set<Int> = [root.number]
            while let parent = byHead[root.baseRefName], seen.insert(parent.number).inserted {
                root = parent
            }
            var chain: [RepositoryPullRequest] = []
            var queue = [root]
            while !queue.isEmpty {
                let next = queue.removeFirst()
                guard placed.insert(next.number).inserted else { continue }
                chain.append(next)
                queue += children[next.headRefName] ?? []
            }
            items.append(chain.count > 1 ? .stack(chain.reversed()) : .single(root))
        }
        return items
    }
}
