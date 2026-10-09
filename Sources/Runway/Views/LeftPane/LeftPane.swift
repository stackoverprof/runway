import SwiftUI
import AppKit

/// A changed set of cards needs a fresh scroll container. AppKit can retain an
/// old clip origin after the lazy stack gets shorter, hiding its first card
/// even though the board model and count still include it. Reordering within
/// the same lane keeps the container so a drag does not jump the scroll.
struct RunwayIssueListIdentity: Hashable {
    let repository: String
    let lane: AssignedIssueLane
    let members: [Int]
    let resetGeneration: Int

    init(repository: String, lane: AssignedIssueLane, issues: [AssignedIssue], resetGeneration: Int) {
        self.repository = repository
        self.lane = lane
        self.members = issues.map(\.number).sorted()
        self.resetGeneration = resetGeneration
    }
}

private struct FocusBoardMenuAnchorKey: PreferenceKey {
    static let defaultValue: CGRect = .zero

    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let next = nextValue()
        if next != .zero { value = next }
    }
}

/// Left pane: a "working now" presence strip on top, then the activity stream.
struct LeftPane: View {
    @Bindable var ws: Workspace
    @Bindable var feed: GitHubFeed
    @State private var showRepoPicker = false
    @State private var showAllPresence = false
    @State private var hoveringNewIssue = false
    @State private var focusBoardMenuOpen = false
    @State private var focusBoardMenuAnchor: CGRect = .zero
    @State private var hoveredFocusBoardMenuItem: Int?
    @State private var assignedIssues = AssignedIssues()
    @State private var pullRequests = PullRequests.shared
    @State private var focusIssueDrag = FocusIssueDrag()
    @State private var feedScrollAnchor = RunwayScrollAnchor()
    @State private var pullScrollAnchor = RunwayScrollAnchor()
    @State private var openIssueScrollAnchor = RunwayScrollAnchor()
    @State private var closedIssueScrollAnchor = RunwayScrollAnchor()
    @State private var issueListResetGeneration = 0
    @State private var issueSearchVisible = false
    @State private var issueSearchQuery = ""
    @State private var feedSearchVisible = false
    @State private var feedSearchQuery = ""
    @State private var prSearchVisible = false
    @State private var prSearchQuery = ""
    @State private var expandedPRAuthor: String?
    @State private var prVisibleCounts: [PRPageKey: Int] = [:]
    @FocusState private var focusedSearchTab: FeedTab?
    @AppStorage(SettingsKey.fireThreshold) private var fireThreshold = 5
    @AppStorage(SettingsKey.brandHeaderStyle) private var brandHeaderStyle = "text"
    @AppStorage(SettingsKey.brandTitle) private var brandTitle = "Activity"
    @AppStorage(SettingsKey.brandLogoFilename) private var brandLogoFilename = ""
    @AppStorage(SettingsKey.focusBoardCollapsed) private var focusBoardCollapsed = false

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

            focusDragOverlay

            if focusBoardMenuOpen {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { focusBoardMenuOpen = false }

                focusBoardDropdown
                    .offset(x: focusBoardMenuAnchor.minX + 16, y: focusBoardMenuAnchor.maxY + 5)
            }
        }
        .coordinateSpace(name: FocusIssueDrag.coordinateSpaceName)
        .onPreferenceChange(FocusBoardMenuAnchorKey.self) {
            focusBoardMenuAnchor = $0
        }
        .onPreferenceChange(RunwayIssueCardFramePreferenceKey.self) {
            focusIssueDrag.updateCardFrames($0)
        }
        .onPreferenceChange(RunwayIssueLaneFramePreferenceKey.self) {
            focusIssueDrag.updateLaneFrames($0)
        }
        .onPreferenceChange(RunwayIssueTabsFramePreferenceKey.self) {
            focusIssueDrag.updateIssueTabsFrame($0)
        }
        .onReceive(NotificationCenter.default.publisher(for: .assignedIssueBacklogOrderReset)) { _ in
            withAnimation(.easeInOut(duration: 0.16)) {
                assignedIssues.resetBacklogOrder()
            }
            issueListResetGeneration &+= 1
        }
        // Coming back to the window refreshes everything, not only the tab in
        // front. Feeds used to be the only source that refreshed here, which is
        // why Pulls and Runway lagged behind it.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            syncAllSources(tick: 15, forceIssuesFullRefresh: true)
        }
        // One clock for all three sources. They used to poll on separate timers,
        // and Pulls and Runway only while their own tab was on screen, so those
        // tabs showed minutes-old data the moment you switched to them.
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
        // The Focus board owns the right pane whatever the left pane is showing,
        // so its repository reconciliation lives here rather than inside the
        // Runway tab. Only the selected tab stays mounted, and hanging this off
        // that tab left the terminals on the old repository until it reappeared.
        .task(id: feed.repo) {
            focusBoardMenuOpen = false
            assignedIssues.restore(repository: feed.repo)
            revealRequestedFocusIssue()
            syncFocusBoard()
            await assignedIssues.revalidate(repository: feed.repo)
            revealRequestedFocusIssue()
            syncFocusBoard()
        }
        .task(id: feed.repo) {
            await assignedIssues.processIssueCommands(repository: feed.repo)
        }
        // Observe the complete Focus records, not only membership. GitHub title
        // edits must refresh the issue-owned terminal header without replacing
        // its stable box and live shell session.
        .onChange(of: assignedIssues.allFocused) { _, _ in
            guard focusIssueDrag.issueNumber == nil else { return }
            syncFocusBoard()
        }
        .onChange(of: assignedIssues.focusBoards) { _, _ in
            guard focusIssueDrag.issueNumber == nil else { return }
            syncFocusBoard()
        }
        .onChange(of: ws.focusIssueRevealRequest) { _, _ in
            revealRequestedFocusIssue()
        }
        .onChange(of: ws.selectedTab) { previousTab, tab in
            focusBoardMenuOpen = false
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
        .task(id: emptySearchIsOpen(for: .runway)) {
            await closeSearchAfterIdle(for: .runway)
        }
        .task(id: emptySearchIsOpen(for: .feeds)) {
            await closeSearchAfterIdle(for: .feeds)
        }
        .task(id: emptySearchIsOpen(for: .pullRequests)) {
            await closeSearchAfterIdle(for: .pullRequests)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(white: 0.035))
    }

    @ViewBuilder
    private var focusDragOverlay: some View {
        if let issueNumber = focusIssueDrag.issueNumber,
           let issue = assignedIssues.issues.first(where: { $0.number == issueNumber }) {
            AssignedIssueCard(
                issue: issue,
                repository: issueRepositoryName
            )
            .frame(
                width: focusIssueDrag.visualSize.width,
                height: focusIssueDrag.visualSize.height
            )
            .offset(
                x: focusIssueDrag.visualOrigin.x,
                y: focusIssueDrag.visualOrigin.y
            )
            .shadow(color: .black.opacity(0.38), radius: 12, y: 5)
            .allowsHitTesting(false)
            .zIndex(Double.greatestFiniteMagnitude)
        }
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
                .accessibilityLabel("Activity")
        } else {
            Text(resolvedBrandTitle)
                .font(.system(size: 27, weight: .bold))
                .foregroundStyle(Color.white.opacity(0.95))
                .lineLimit(1)
        }
    }

    private var resolvedBrandTitle: String {
        let title = brandTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? "Activity" : title
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
        .pointerCursor()
        .popover(isPresented: $showRepoPicker, arrowEdge: .bottom) {
            RepoPicker(repos: feed.availableRepos, current: feed.repo) { picked in
                feed.setRepo(picked)
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
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }

    // MARK: Activity stream
    @State private var pulled = false

    private var subHeader: some View {
        HStack(alignment: .center, spacing: 8) {
            if ws.selectedTab == .runway {
                HStack(spacing: 6) {
                    Button {
                        focusBoardMenuOpen.toggle()
                    } label: {
                        Text(assignedIssues.focusBoardCount == 1
                             ? subHeaderText
                             : "\(subHeaderText) · \(assignedIssues.activeFocusBoardIndex + 1)/\(assignedIssues.focusBoardCount)")
                            .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                            .foregroundStyle(Color.white.opacity(0.3))
                            .tracking(0.8)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .fixedSize()
                    .pointerCursor()
                    .disabled(feed.repo.isEmpty || !assignedIssues.hasSnapshot)
                    .help("Switch Focus board")

                    Button {
                        withAnimation(focusBoardCollapseAnimation) {
                            focusBoardCollapsed.toggle()
                        }
                    } label: {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 7.5, weight: .bold))
                            .rotationEffect(.degrees(focusBoardCollapsed ? -90 : 0))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .pointerCursor()
                    .help(focusBoardCollapsed ? "Show Focus board" : "Hide Focus board")
                }
            } else {
                Text(subHeaderText)
                    .opacity(ws.selectedTab == .feeds ? taglineOpacity : 1)
            }
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
        .background {
            GeometryReader { geometry in
                Color.clear.preference(
                    key: FocusBoardMenuAnchorKey.self,
                    value: geometry.frame(in: .named(FocusIssueDrag.coordinateSpaceName))
                )
            }
        }
    }

    private var focusBoardCollapseAnimation: Animation {
        .spring(response: 0.34, dampingFraction: 0.86)
    }

    private var subHeaderText: String {
        switch ws.selectedTab {
        case .runway: "ON TODAY'S MISSIONS"
        case .feeds: displayedTagline
        case .pullRequests: "PULL REQUESTS BY DEV"
        }
    }

    private var focusBoardDropdown: some View {
        VStack(spacing: 2) {
            ForEach(0..<assignedIssues.focusBoardCount, id: \.self) { index in
                focusBoardDropdownRow(
                    title: "Board \(index + 1)",
                    detail: "\(assignedIssues.focusBoards.boards[index].count)/5",
                    selected: index == assignedIssues.activeFocusBoardIndex,
                    id: index
                ) {
                    assignedIssues.selectFocusBoard(index)
                    focusBoardCollapsed = false
                    syncFocusBoard()
                }
            }

            Rectangle()
                .fill(Color.white.opacity(0.09))
                .frame(height: 1)
                .padding(.horizontal, 6)
                .padding(.vertical, 4)

            focusBoardDropdownRow(
                title: "New Focus board",
                detail: nil,
                selected: false,
                id: -1
            ) {
                assignedIssues.createFocusBoard()
                focusBoardCollapsed = false
                syncFocusBoard()
            }
        }
        .padding(6)
        .frame(width: 194)
        .background(RoundedRectangle(cornerRadius: 9).fill(Color(white: 0.10)))
        .overlay {
            RoundedRectangle(cornerRadius: 9)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.45), radius: 12, y: 5)
    }

    private func focusBoardDropdownRow(
        title: String,
        detail: String?,
        selected: Bool,
        id: Int,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            action()
            focusBoardMenuOpen = false
        } label: {
            HStack(spacing: 8) {
                Text(title)
                Spacer(minLength: 4)
                if let detail {
                    Text(detail)
                        .foregroundStyle(Color.white.opacity(0.38))
                }
                if selected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.5))
                }
            }
            .font(.system(size: 11, weight: selected ? .semibold : .medium, design: .monospaced))
            .foregroundStyle(Color.white.opacity(selected ? 0.9 : 0.7))
            .padding(.horizontal, 9)
            .frame(height: 29)
            .background {
                RoundedRectangle(cornerRadius: 5)
                    .fill(Color.white.opacity(selected ? 0.09 : hoveredFocusBoardMenuItem == id ? 0.06 : 0))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .pointerCursor()
        .onHover { hoveredFocusBoardMenuItem = $0 ? id : nil }
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
            prVisibleCounts.removeAll()
            pullRequests.restore(repository: feed.repo)
            await pullRequests.revalidate(repository: feed.repo, minimumAge: 30)
        }
        // Changing the window resets paging: the counts and the expanded
        // developer belong to the window that produced them.
        .onChange(of: ws.prTimeframe) { _, _ in
            expandedPRAuthor = nil
            prVisibleCounts.removeAll()
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
            if developerText.localizedCaseInsensitiveContains(query) {
                return developer
            }
            let matches = developer.pullRequests.filter { pullRequest in
                "\(GitHubNumber.reference(pullRequest.number)) \(pullRequest.title) \(pullRequest.headRefName) \(pullRequest.baseRefName)"
                    .localizedCaseInsensitiveContains(query)
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
                    if expanded {
                        prVisibleCounts = prVisibleCounts.filter {
                            $0.key.login != developer.login.lowercased()
                        }
                    }
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
                        prCount("Draft", developer.draftCount, color: Self.prOrange)
                    }
                    if developer.openCount > 0 {
                        prCount("Open", developer.openCount, color: Self.prGreen)
                    }
                    if developer.mergedCount > 0 {
                        prCount("Merged", developer.mergedCount, color: Self.prPurple)
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
                VStack(alignment: .leading, spacing: 10) {
                    pullRequestSection(
                        "DRAFT",
                        developerLogin: developer.login,
                        pullRequests: developer.pullRequests.filter {
                            $0.isOpen && $0.isDraft
                        },
                        color: Self.prOrange
                    )
                    pullRequestSection(
                        "OPEN",
                        developerLogin: developer.login,
                        pullRequests: developer.pullRequests.filter {
                            $0.isOpen && !$0.isDraft
                        },
                        color: Self.prGreen
                    )
                    pullRequestSection(
                        "MERGED",
                        developerLogin: developer.login,
                        pullRequests: developer.pullRequests.filter(\.isMerged),
                        color: Self.prPurple
                    )
                    pullRequestSection(
                        "CLOSED",
                        developerLogin: developer.login,
                        pullRequests: developer.pullRequests.filter { !$0.isOpen && !$0.isMerged },
                        color: Color.white.opacity(0.38)
                    )
                }
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

    private static let prGreen = Color(red: 0.18, green: 0.78, blue: 0.38)
    private static let prOrange = Color(red: 0.94, green: 0.62, blue: 0.20)
    private static let prPurple = Color(red: 0.64, green: 0.42, blue: 0.94)
    private static let prPageSize = 20

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

    @ViewBuilder
    private func pullRequestSection(
        _ title: String,
        developerLogin: String,
        pullRequests: [RepositoryPullRequest],
        color: Color
    ) -> some View {
        if !pullRequests.isEmpty {
            let pageKey = PRPageKey(login: developerLogin.lowercased(), section: title)
            let visibleCount = min(
                prVisibleCounts[pageKey] ?? Self.prPageSize,
                pullRequests.count
            )
            let remainingCount = pullRequests.count - visibleCount
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 5) {
                    Circle().fill(color).frame(width: 5, height: 5)
                    Text("\(title)  \(pullRequests.count)")
                        .font(.system(size: 8.5, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Color.white.opacity(0.32))
                    Spacer()
                    if remainingCount > 0 {
                        Text("SHOWING \(visibleCount)")
                            .font(.system(size: 7.5, weight: .medium, design: .monospaced))
                            .foregroundStyle(Color.white.opacity(0.20))
                    }
                }
                ForEach(Array(pullRequests.prefix(visibleCount))) { pullRequest in
                    pullRequestRow(pullRequest, color: color)
                }
                if remainingCount > 0 {
                    Button {
                        withAnimation(.easeInOut(duration: 0.16)) {
                            prVisibleCounts[pageKey] = min(
                                visibleCount + Self.prPageSize,
                                pullRequests.count
                            )
                        }
                    } label: {
                        HStack {
                            Text("Show next \(min(Self.prPageSize, remainingCount))")
                            Spacer()
                            Text("\(remainingCount) remaining")
                                .foregroundStyle(Color.white.opacity(0.24))
                        }
                        .font(.system(size: 8.5, weight: .medium, design: .monospaced))
                        .foregroundStyle(Color.white.opacity(0.45))
                        .padding(.horizontal, 8)
                        .frame(height: 26)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.white.opacity(0.025))
                        )
                        .contentShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                    .pointerCursor()
                }
            }
        }
    }

    private func pullRequestRow(_ pullRequest: RepositoryPullRequest, color: Color) -> some View {
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
                    if let timeframe = pullRequestTimeframeText(pullRequest) {
                        Text(timeframe)
                            .font(.system(size: 8.5, design: .monospaced))
                            .foregroundStyle(Color.white.opacity(0.24))
                    }
                }
                HStack(spacing: 5) {
                    Text(pullRequest.headRefName)
                    Image(systemName: "arrow.right")
                        .font(.system(size: 7, weight: .semibold))
                    Text(pullRequest.baseRefName)
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
    }

    private func pullRequestTimeframeText(_ pullRequest: RepositoryPullRequest) -> String? {
        if pullRequest.isMerged {
            let mergedAt = pullRequest.mergedAt ?? pullRequest.closedAt ?? pullRequest.updatedAt
            return "merged \(relativePullRequestDate(mergedAt))"
        }
        guard pullRequest.isOpen, !pullRequest.isDraft else { return nil }
        return PullRequestDurationFormatter.string(Date().timeIntervalSince(pullRequest.createdAt))
    }

    private func relativePullRequestDate(_ date: Date) -> String {
        let seconds = max(0, Int(Date().timeIntervalSince(date)))
        if seconds < 60 { return "just now" }
        let minutes = seconds / 60
        if minutes == 1 { return "a minute ago" }
        if minutes < 60 { return "\(minutes) minutes ago" }
        let hours = minutes / 60
        if hours == 1 { return "an hour ago" }
        if hours < 24 { return "\(hours) hours ago" }
        return clock(date)
    }

    private var runwayTab: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !focusBoardCollapsed {
                runwayEmptyContainer
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
                    .layoutPriority(2)
                    .transition(
                        .opacity
                            .combined(with: .move(edge: .top))
                            .combined(with: .scale(scale: 0.97, anchor: .top))
                    )
            }

            runwayBacklog
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .clipped()
        }
        .animation(focusBoardCollapseAnimation, value: focusBoardCollapsed)
        .animation(.spring(response: 0.38, dampingFraction: 0.85), value: ws.runwayIssueTab)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .clipped()
    }

    private var runwayBacklog: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(spacing: 8) {
                runwayIssueTabs

                if issueSearchVisible {
                    issueSearchField
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 16)
                .padding(.bottom, 10)

            if assignedIssues.loading && assignedIssues.issues.isEmpty {
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = assignedIssues.error, assignedIssues.issues.isEmpty {
                feedNotice(error, systemImage: "exclamationmark.triangle")
            } else if assignedIssues.issues.isEmpty, !feed.repo.isEmpty {
                newIssuePlaceholder
            } else {
                GeometryReader { geo in
                    HStack(spacing: 0) {
                        runwayIssueList(filteredOpenIssues, lane: .open)
                            .frame(width: geo.size.width)
                        runwayIssueList(filteredClosedIssues, lane: .closed)
                            .frame(width: geo.size.width)
                    }
                    .offset(x: -CGFloat(runwayIssueTabIndex) * geo.size.width)
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
        .onChange(of: issueSearchQuery) { _, _ in
            updateIssueSearchTab()
        }
        .onChange(of: filteredOpenIssues.count) { _, _ in
            updateIssueSearchTab()
        }
        .onChange(of: filteredClosedIssues.count) { _, _ in
            updateIssueSearchTab()
        }
    }

    private var runwayEmptyContainer: some View {
        ZStack(alignment: .topLeading) {
            if assignedIssues.focused.isEmpty,
               focusIssueDrag.focusPreviewKey == nil {
                focusEmptyState
                    .transition(.opacity)
            }

            VStack(alignment: .leading, spacing: 8) {
                ForEach(assignedIssues.focused) { issue in
                    if focusIssueDrag.shouldInsertFocusPlaceholder(before: issue.number),
                       !assignedIssues.focusedIssueNumbers.contains(
                           focusIssueDrag.issueNumber ?? -1
                       ),
                       assignedIssues.focused.count < 5 {
                        Color.clear
                            .frame(height: focusIssueDrag.visualSize.height)
                    }

                    AssignedIssueCard(
                        issue: issue,
                        repository: issueRepositoryName,
                        onClosedChange: { closed in
                            withAnimation(.easeOut(duration: 0.18)) {
                                _ = assignedIssues.setClosed(
                                    issueNumber: issue.number,
                                    closed: closed
                                )
                            }
                        },
                        onRename: { newTitle in
                            if assignedIssues.renameIssue(
                                issueNumber: issue.number,
                                newTitle: newTitle
                            ) {
                                syncFocusBoard()
                            }
                        },
                        onRemoveFromFocus: {
                            assignedIssues.removeFromFocus(issueNumber: issue.number)
                        }
                    )
                    .background {
                        GeometryReader { proxy in
                            Color.clear.preference(
                                key: RunwayIssueCardFramePreferenceKey.self,
                                value: [
                                    RunwayIssueCardKey(
                                        lane: .focus,
                                        issueNumber: issue.number
                                    ): proxy.frame(in: .named(FocusIssueDrag.coordinateSpaceName))
                                ]
                            )
                        }
                    }
                    .opacity(focusIssueDrag.issueNumber == issue.number ? 0 : 1)
                    .animation(nil, value: focusIssueDrag.issueNumber)
                    .simultaneousGesture(issueDragGesture(for: issue, lane: .focus))
                    .frame(
                        height: focusIssueDrag.shouldReleaseFocusSlot(for: issue.number)
                            ? 0
                            : nil
                    )
                    .clipped()
                }

                if focusIssueDrag.shouldAppendFocusPlaceholder,
                   !assignedIssues.focusedIssueNumbers.contains(
                       focusIssueDrag.issueNumber ?? -1
                   ),
                   assignedIssues.focused.count < 5 {
                    Color.clear
                        .frame(height: focusIssueDrag.visualSize.height)
                }
            }
        }
        .animation(.easeInOut(duration: 0.16), value: assignedIssues.focusedIssueNumbers)
        .animation(.easeInOut(duration: 0.16), value: focusIssueDrag.focusPreviewKey)
        .padding(8)
        .frame(maxWidth: .infinity, minHeight: 76, alignment: .topLeading)
        .background {
            GeometryReader { proxy in
                Color.clear.preference(
                    key: RunwayIssueLaneFramePreferenceKey.self,
                    value: [
                        .focus: proxy.frame(in: .named(FocusIssueDrag.coordinateSpaceName))
                    ]
                )
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 9)
                .fill(Color.white.opacity(assignedIssues.focused.isEmpty ? 0.015 : 0.025))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 9)
                .stroke(
                    Color.white.opacity(0.11),
                    style: StrokeStyle(
                        lineWidth: 1,
                        dash: assignedIssues.focused.isEmpty ? [5, 5] : []
                    )
                )
        }
    }

    /// Nothing at all is assigned in this repository. Runway only ever shows
    /// issues assigned to you, so an empty board usually means "nothing is
    /// assigned yet" rather than "nothing exists". Say so, and open GitHub's
    /// new-issue form with the assignee already filled in.
    private var newIssuePlaceholder: some View {
        VStack(spacing: 11) {
            Image(systemName: "tray")
                .font(.system(size: 21, weight: .light))
                .foregroundStyle(Color.white.opacity(0.3))

            VStack(spacing: 5) {
                Text("No issues assigned to you")
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.72))
                Text("Runway tracks the issues you are assigned to. Create one in \(issueRepositoryName) and assign it to yourself to see it here.")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.white.opacity(0.42))
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 5) {
                Text("New issue on GitHub")
                Image(systemName: "arrow.up.forward")
                    .font(.system(size: 9, weight: .semibold))
            }
            .font(.system(size: 11.5, weight: .medium))
            .foregroundStyle(Color.white.opacity(hoveringNewIssue ? 0.95 : 0.72))
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .background(
                Capsule().fill(Color.white.opacity(hoveringNewIssue ? 0.17 : 0.1))
            )
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 22)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 9)
                .fill(Color(white: hoveringNewIssue ? 0.085 : 0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9)
                .strokeBorder(
                    Color.white.opacity(hoveringNewIssue ? 0.22 : 0.12),
                    style: StrokeStyle(lineWidth: 1, dash: [4, 3])
                )
        )
        .contentShape(RoundedRectangle(cornerRadius: 9))
        .onHover { hoveringNewIssue = $0 }
        .pointerCursor()
        .onTapGesture { openNewIssuePage() }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    /// GitHub prefills assignees from the query string, so the issue lands in
    /// Runway as soon as it is submitted, with no second trip to the sidebar.
    private func openNewIssuePage() {
        let repository = feed.repo
        guard !repository.isEmpty,
              var components = URLComponents(
                  string: "https://github.com/\(repository)/issues/new"
              ) else { return }
        Task {
            if let login = await GH.viewerLogin() {
                components.queryItems = [URLQueryItem(name: "assignees", value: login)]
            }
            guard let url = components.url else { return }
            NSWorkspace.shared.open(url)
        }
    }

    private var focusEmptyState: some View {
        VStack(spacing: 7) {
            Image(systemName: "rectangle.stack.badge.plus")
                .font(.system(size: 18, weight: .light))
            Text("Drag an issue here to open its terminal")
                .font(.system(size: 10, weight: .regular, design: .monospaced))
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
        .foregroundStyle(Color.white.opacity(0.25))
        .frame(maxWidth: .infinity, minHeight: 60, alignment: .center)
        .allowsHitTesting(false)
    }

    private func issueDragGesture(
        for issue: AssignedIssue,
        lane: AssignedIssueLane
    ) -> some Gesture {
        DragGesture(
            minimumDistance: 4,
            coordinateSpace: .named(FocusIssueDrag.coordinateSpaceName)
        )
        .onChanged { value in
            guard !focusIssueDrag.isLanding else { return }
            if focusIssueDrag.issueNumber == nil {
                guard let frame = focusIssueDrag.frame(for: issue.number, in: lane) else { return }
                focusIssueDrag.begin(
                    issueNumber: issue.number,
                    lane: lane,
                    frame: frame,
                    pointer: value.startLocation
                )
                ws.isFocusCardDragging = true
            }
            guard focusIssueDrag.issueNumber == issue.number else { return }
            focusIssueDrag.move(pointer: value.location)
            autoScrollBacklog(pointer: value.location)

            let hoveredLane = focusIssueDrag.lane(at: value.location)
            if lane == .focus, focusIssueDrag.isCrossingIssueTabs {
                let displayedLane: AssignedIssueLane = ws.runwayIssueTab == .open ? .open : .closed
                let previewLane: AssignedIssueLane? = switch hoveredLane {
                case .open, .closed: hoveredLane
                case nil: displayedLane
                case .focus: nil
                }
                focusIssueDrag.updateBacklogPreview(
                    lane: previewLane,
                    before: previewLane.map {
                        focusIssueDrag.insertionTarget(
                            at: value.location,
                            in: $0,
                            excluding: issue.number
                        )
                    } ?? nil
                )
            } else {
                focusIssueDrag.clearBacklogPreview()
            }

            if lane != .focus, focusIssueDrag.isCrossingIssueTabs {
                focusIssueDrag.updateFocusPreview(
                    before: focusIssueDrag.insertionTarget(
                        at: value.location,
                        in: .focus,
                        excluding: issue.number
                    )
                )
            } else {
                focusIssueDrag.clearFocusPreview()
            }

            guard hoveredLane == lane else {
                focusIssueDrag.clearTarget()
                return
            }
            guard let targetIssueNumber = focusIssueDrag.targetIssue(
                at: value.location,
                in: lane,
                excluding: issue.number
            ) else {
                focusIssueDrag.clearTarget()
                return
            }
            guard focusIssueDrag.shouldMove(to: targetIssueNumber) else { return }
            _ = withAnimation(.easeInOut(duration: 0.16)) {
                assignedIssues.move(
                    issueNumber: issue.number,
                    from: lane,
                    to: lane,
                    before: targetIssueNumber
                )
            }
        }
        .onEnded { value in
            stopBacklogAutoScroll()
            guard focusIssueDrag.issueNumber == issue.number,
                  let sourceLane = focusIssueDrag.sourceLane else { return }
            let proposedLane = focusIssueDrag.proposedLane(
                at: value.location,
                fallback: sourceLane,
                displayedBacklogLane: ws.runwayIssueTab == .open ? .open : .closed
            )
            let targetIssueNumber = sourceLane == proposedLane
                ? focusIssueDrag.targetIssue(
                    at: value.location,
                    in: proposedLane,
                    excluding: issue.number
                )
                : focusIssueDrag.insertionTarget(
                    at: value.location,
                    in: proposedLane,
                    excluding: issue.number
                )
            let accepted = sourceLane == proposedLane || assignedIssues.move(
                issueNumber: issue.number,
                from: sourceLane,
                to: proposedLane,
                before: targetIssueNumber
            )
            let landingLane = accepted ? proposedLane : sourceLane
            focusIssueDrag.prepareLanding()
            DispatchQueue.main.async {
                let destination = focusIssueDrag.landingFrame(for: landingLane)
                withAnimation(
                    .spring(response: 0.28, dampingFraction: 0.88),
                    completionCriteria: .removed
                ) {
                    focusIssueDrag.land(at: destination.origin)
                } completion: {
                    focusIssueDrag.reset()
                    ws.isFocusCardDragging = false
                    syncFocusBoard()
                }
            }
        }
    }

    private var runwayIssueTabs: some View {
        HStack(spacing: 0) {
            ForEach(RunwayIssueTab.allCases, id: \.rawValue) { tab in
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { ws.runwayIssueTab = tab }
                } label: {
                    HStack(spacing: 5) {
                        Text(tab.rawValue)
                        Text("\(assignedIssueCount(for: tab))")
                            .foregroundStyle(Color.white.opacity(0.35))
                    }
                    .font(.system(size: 10.5, weight: ws.runwayIssueTab == tab ? .semibold : .medium))
                    .foregroundStyle(ws.runwayIssueTab == tab ? Color.white.opacity(0.9) : Color.white.opacity(0.4))
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
        .background {
            GeometryReader { proxy in
                Color.clear.preference(
                    key: RunwayIssueTabsFramePreferenceKey.self,
                    value: proxy.frame(in: .named(FocusIssueDrag.coordinateSpaceName))
                )
            }
        }
    }

    private var issueSearchField: some View {
        searchField(
            placeholder: "Search issues",
            text: $issueSearchQuery,
            tab: .runway
        )
    }

    private func searchField(
        placeholder: String,
        text: Binding<String>,
        tab: FeedTab
    ) -> some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.30))

            TextField(placeholder, text: text)
                .textFieldStyle(.plain)
                .font(.system(size: 10.5, design: .monospaced))
                .foregroundStyle(Color.white.opacity(0.82))
                .focused($focusedSearchTab, equals: tab)

            if !text.wrappedValue.isEmpty {
                Button {
                    text.wrappedValue = ""
                    focusedSearchTab = tab
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 10.5))
                        .foregroundStyle(Color.white.opacity(0.28))
                }
                .buttonStyle(.plain)
                .pointerCursor()
                .help("Clear search")
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 30)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.035)))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(
                    Color.white.opacity(focusedSearchTab == tab ? 0.15 : 0.07),
                    lineWidth: 1
                )
        )
    }

    private func toggleSearch(for tab: FeedTab) {
        var willShow = false
        withAnimation(.easeInOut(duration: 0.16)) {
            switch tab {
            case .runway:
                issueSearchVisible.toggle()
                willShow = issueSearchVisible
                if !willShow {
                    issueSearchQuery = ""
                }
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
            return issueSearchVisible
                && issueSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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
                issueSearchVisible = false
                issueSearchQuery = ""
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
            feedEventSearchText($0).localizedCaseInsensitiveContains(normalized)
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

    private func runwayIssueList(
        _ issues: [AssignedIssue],
        lane: AssignedIssueLane
    ) -> some View {
        ZStack(alignment: .top) {
            if issues.isEmpty, !focusIssueDrag.shouldAppendBacklogPlaceholder(in: lane) {
                issueLaneEmptyState(lane)
                    .transition(.opacity)
            }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                ForEach(issues) { issue in
                    if focusIssueDrag.shouldInsertBacklogPlaceholder(
                        before: issue.number,
                        in: lane
                    ) {
                        Color.clear
                            .frame(height: focusIssueDrag.visualSize.height)
                    }

                    AssignedIssueCard(
                        issue: issue,
                        repository: issueRepositoryName,
                        onClosedChange: { closed in
                            withAnimation(.easeOut(duration: 0.18)) {
                                _ = assignedIssues.setClosed(
                                    issueNumber: issue.number,
                                    closed: closed
                                )
                            }
                        },
                        onRename: { newTitle in
                            if assignedIssues.renameIssue(
                                issueNumber: issue.number,
                                newTitle: newTitle
                            ) {
                                syncFocusBoard()
                            }
                        }
                    )
                    .transition(.opacity)
                    .background {
                        GeometryReader { proxy in
                            Color.clear.preference(
                                key: RunwayIssueCardFramePreferenceKey.self,
                                value: [
                                    RunwayIssueCardKey(
                                        lane: lane,
                                        issueNumber: issue.number
                                    ): proxy.frame(in: .named(FocusIssueDrag.coordinateSpaceName))
                                ]
                            )
                        }
                    }
                    .opacity(focusIssueDrag.issueNumber == issue.number ? 0 : 1)
                    .animation(nil, value: focusIssueDrag.issueNumber)
                    .simultaneousGesture(issueDragGesture(for: issue, lane: lane))
                    .frame(
                        height: focusIssueDrag.shouldReleaseBacklogSlot(
                            for: issue.number,
                            in: lane
                        ) ? 0 : nil
                    )
                    .clipped()
                }

                if focusIssueDrag.shouldAppendBacklogPlaceholder(in: lane) {
                    Color.clear
                        .frame(height: focusIssueDrag.visualSize.height)
                }
                }
                .animation(.easeInOut(duration: 0.16), value: focusIssueDrag.backlogPreviewKey)
                .animation(
                    .easeInOut(duration: 0.16),
                    value: focusIssueDrag.isCrossingIssueTabs
                )
                .animation(.easeOut(duration: 0.18), value: issues.map(\.number))
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
                .scrollAnchor(issueScrollAnchor(for: lane))
            }
            .contentMargins(.top, 0, for: .scrollContent)
            .scrollIndicators(.hidden)
            .id(RunwayIssueListIdentity(
                repository: feed.repo,
                lane: lane,
                issues: issues,
                resetGeneration: issueListResetGeneration
            ))
        }
        .background {
            GeometryReader { proxy in
                Color.clear.preference(
                    key: RunwayIssueLaneFramePreferenceKey.self,
                    value: [lane: proxy.frame(in: .named(FocusIssueDrag.coordinateSpaceName))]
                )
            }
        }
    }

    private func issueLaneEmptyState(_ lane: AssignedIssueLane) -> some View {
        let searching = issueSearchVisible
            && !issueSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let isOpen = lane == .open
        let title = searching
            ? "No matching \(isOpen ? "open" : "closed") issues"
            : "No \(isOpen ? "open" : "closed") issues"
        let detail = searching
            ? "Try another search."
            : isOpen
                ? "Assigned issues that are open will appear here."
                : "Issues you close will appear here."

        return VStack(spacing: 8) {
            Image(systemName: searching ? "magnifyingglass" : isOpen ? "circle.dashed" : "checkmark.circle")
                .font(.system(size: 19, weight: .light))
                .foregroundStyle(Color.white.opacity(0.28))
            Text(title)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.62))
            Text(detail)
                .font(.system(size: 11))
                .foregroundStyle(Color.white.opacity(0.36))
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 24)
        .padding(.top, 44)
        .frame(maxWidth: .infinity, alignment: .center)
        .allowsHitTesting(false)
    }

    private var runwayIssueTabIndex: Int {
        ws.runwayIssueTab == .open ? 0 : 1
    }

    private func assignedIssueCount(for tab: RunwayIssueTab) -> Int {
        tab == .open ? filteredOpenIssues.count : filteredClosedIssues.count
    }

    private var filteredOpenIssues: [AssignedIssue] {
        filteredIssues(assignedIssues.open)
    }

    private var filteredClosedIssues: [AssignedIssue] {
        filteredIssues(assignedIssues.closed)
    }

    private func filteredIssues(_ issues: [AssignedIssue]) -> [AssignedIssue] {
        let query = issueSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard issueSearchVisible, !query.isEmpty else { return issues }
        return issues.filter {
            AssignedIssue.matchesSearchQuery(
                query,
                issue: $0,
                repositoryName: issueRepositoryName
            )
        }
    }

    private func updateIssueSearchTab() {
        guard issueSearchVisible else { return }

        let currentCount = assignedIssueCount(for: ws.runwayIssueTab)
        guard currentCount == 0 else { return }

        let otherTab: RunwayIssueTab = ws.runwayIssueTab == .open ? .closed : .open
        guard assignedIssueCount(for: otherTab) > 0 else { return }

        withAnimation(.easeInOut(duration: 0.15)) {
            ws.runwayIssueTab = otherTab
        }
    }

    private var issueRepositoryName: String {
        feed.repo.split(separator: "/").last.map(String.init) ?? feed.repo
    }

    private func syncFocusBoard() {
        guard assignedIssues.hasSnapshot else { return }
        ws.syncFocusBoard(
            issues: assignedIssues.allFocused,
            visibleIssueNumbers: assignedIssues.focusedIssueNumbers,
            selectedBoardIndex: assignedIssues.activeFocusBoardIndex,
            repository: feed.repo
        )
    }

    private func revealRequestedFocusIssue() {
        guard let request = ws.focusIssueRevealRequest,
              request.repository.caseInsensitiveCompare(feed.repo) == .orderedSame,
              assignedIssues.hasSnapshot,
              let index = assignedIssues.boardIndex(containing: request.issueNumber) else { return }
        assignedIssues.selectFocusBoard(index)
        ws.focusIssueRevealRequest = nil
        syncFocusBoard()
    }

    private func revalidateFocusBoard(minimumAge: TimeInterval = 15) {
        Task {
            await assignedIssues.revalidate(
                repository: feed.repo,
                minimumAge: minimumAge
            )
            syncFocusBoard()
        }
    }

    // MARK: Sync

    /// Refresh all three sources off one tick. Started together so the feed, the
    /// board and the pull requests describe the same moment; each service still
    /// throttles itself, so the tab in front leads and the others follow closely
    /// instead of drifting minutes behind.
    private func syncAllSources(tick: TimeInterval, forceIssuesFullRefresh: Bool = false) {
        let ages = RepositorySyncCadence.ages(for: ws.selectedTab, tick: tick)
        Task { await feed.refresh(minimumAge: ages.feed) }
        revalidateFocusBoard(minimumAge: forceIssuesFullRefresh ? 0 : ages.issues)
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
            revalidateFocusBoard(minimumAge: minimumAge)
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
        if ws.selectedTab == .runway {
            issueListResetGeneration &+= 1
        } else {
            scrollAnchor(for: ws.selectedTab).scrollToTop()
        }
        refreshSource(for: ws.selectedTab, minimumAge: 0)
        // A refresh that turns up nothing new still has to look like one. The
        // tagline retypes on the tap itself rather than on an event arriving,
        // and skips the burst guard because the user asked for it by hand.
        if ws.selectedTab == .feeds, taglineEnabled { rotateTagline() }
    }

    private func scrollAnchor(for tab: FeedTab) -> RunwayScrollAnchor {
        switch tab {
        case .runway: issueScrollAnchor(for: ws.runwayIssueTab == .open ? .open : .closed)
        case .feeds: feedScrollAnchor
        case .pullRequests: pullScrollAnchor
        }
    }

    private func issueScrollAnchor(for lane: AssignedIssueLane) -> RunwayScrollAnchor {
        lane == .closed ? closedIssueScrollAnchor : openIssueScrollAnchor
    }

    /// Dragging a card against the top or bottom of the backlog scrolls it, so an
    /// issue can be moved past the edge of a list taller than the pane.
    private func autoScrollBacklog(pointer: CGPoint) {
        let displayed: AssignedIssueLane = ws.runwayIssueTab == .open ? .open : .closed
        for lane in [AssignedIssueLane.open, .closed] {
            let anchor = issueScrollAnchor(for: lane)
            // A short overshoot band past each edge keeps scrolling while the
            // card is dragged beyond the list, which is exactly when the last
            // row is still out of reach.
            guard lane == displayed,
                  let frame = focusIssueDrag.laneFrames[lane],
                  pointer.y > frame.minY - 64,
                  pointer.y < frame.maxY + 64
            else {
                anchor.stopAutoScroll()
                continue
            }
            anchor.autoScroll(pointerY: pointer.y, in: frame)
        }
    }

    private func stopBacklogAutoScroll() {
        issueScrollAnchor(for: .open).stopAutoScroll()
        issueScrollAnchor(for: .closed).stopAutoScroll()
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

private struct PRPageKey: Hashable {
    let login: String
    let section: String
}

private struct RunwayIssueCardKey: Hashable {
    let lane: AssignedIssueLane
    let issueNumber: Int
}

private struct RunwayIssueCardFramePreferenceKey: PreferenceKey {
    static let defaultValue: [RunwayIssueCardKey: CGRect] = [:]

    static func reduce(
        value: inout [RunwayIssueCardKey: CGRect],
        nextValue: () -> [RunwayIssueCardKey: CGRect]
    ) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

private struct RunwayIssueLaneFramePreferenceKey: PreferenceKey {
    static let defaultValue: [AssignedIssueLane: CGRect] = [:]

    static func reduce(
        value: inout [AssignedIssueLane: CGRect],
        nextValue: () -> [AssignedIssueLane: CGRect]
    ) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

private struct RunwayIssueTabsFramePreferenceKey: PreferenceKey {
    static let defaultValue: CGRect = .zero

    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let next = nextValue()
        if next != .zero { value = next }
    }
}

@MainActor @Observable private final class FocusIssueDrag {
    static let coordinateSpaceName = "RunwayFocusReorder"

    private(set) var issueNumber: Int?
    private(set) var visualOrigin: CGPoint = .zero
    private(set) var visualSize: CGSize = .zero
    private(set) var cardFrames: [RunwayIssueCardKey: CGRect] = [:]
    private(set) var laneFrames: [AssignedIssueLane: CGRect] = [:]
    private(set) var issueTabsFrame: CGRect = .zero
    private(set) var sourceLane: AssignedIssueLane?
    private(set) var isLanding = false
    private var startingFrame: CGRect = .zero
    private var crossingBoundaryY: CGFloat?
    private var hasCrossedIssueTabs = false
    private var backlogPreviewLane: AssignedIssueLane?
    private var backlogPreviewTargetIssueNumber: Int?
    private var focusPreviewTargetIssueNumber: Int?
    private var isFocusPreviewActive = false
    private var grabOffset: CGPoint = .zero
    private var lastTargetIssueNumber: Int?

    func updateCardFrames(_ frames: [RunwayIssueCardKey: CGRect]) {
        guard cardFrames != frames else { return }
        cardFrames = frames
    }

    func updateLaneFrames(_ frames: [AssignedIssueLane: CGRect]) {
        guard laneFrames != frames else { return }
        laneFrames = frames
    }

    func updateIssueTabsFrame(_ frame: CGRect) {
        guard issueTabsFrame != frame else { return }
        issueTabsFrame = frame
    }

    func frame(for issueNumber: Int, in lane: AssignedIssueLane) -> CGRect? {
        cardFrames[RunwayIssueCardKey(lane: lane, issueNumber: issueNumber)]
    }

    func begin(
        issueNumber: Int,
        lane: AssignedIssueLane,
        frame: CGRect,
        pointer: CGPoint
    ) {
        self.issueNumber = issueNumber
        sourceLane = lane
        startingFrame = frame
        crossingBoundaryY = issueTabsFrame == .zero ? nil : issueTabsFrame.midY
        visualOrigin = frame.origin
        visualSize = frame.size
        grabOffset = CGPoint(
            x: pointer.x - frame.minX,
            y: pointer.y - frame.minY
        )
        lastTargetIssueNumber = nil
    }

    func move(pointer: CGPoint) {
        visualOrigin = CGPoint(
            x: pointer.x - grabOffset.x,
            y: pointer.y - grabOffset.y
        )
        guard let crossingBoundaryY else { return }
        let visualFrame = CGRect(origin: visualOrigin, size: visualSize)
        let crossed = sourceLane == .focus
            ? visualFrame.maxY >= crossingBoundaryY
            : visualFrame.minY <= crossingBoundaryY
        if crossed != hasCrossedIssueTabs {
            withAnimation(.easeInOut(duration: 0.16)) {
                hasCrossedIssueTabs = crossed
            }
        }
    }

    var focusPreviewKey: Int? {
        guard isFocusPreviewActive else { return nil }
        return focusPreviewTargetIssueNumber ?? -1
    }

    func updateFocusPreview(before targetIssueNumber: Int?) {
        guard !isFocusPreviewActive
                || focusPreviewTargetIssueNumber != targetIssueNumber else { return }
        withAnimation(.easeInOut(duration: 0.16)) {
            isFocusPreviewActive = true
            focusPreviewTargetIssueNumber = targetIssueNumber
        }
    }

    func clearFocusPreview() {
        guard isFocusPreviewActive else { return }
        withAnimation(.easeInOut(duration: 0.16)) {
            isFocusPreviewActive = false
            focusPreviewTargetIssueNumber = nil
        }
    }

    func shouldInsertFocusPlaceholder(before issueNumber: Int) -> Bool {
        isFocusPreviewActive && focusPreviewTargetIssueNumber == issueNumber
    }

    var shouldAppendFocusPlaceholder: Bool {
        isFocusPreviewActive && focusPreviewTargetIssueNumber == nil
    }

    var isCrossingIssueTabs: Bool {
        hasCrossedIssueTabs
    }

    func shouldReleaseFocusSlot(for issueNumber: Int) -> Bool {
        self.issueNumber == issueNumber && sourceLane == .focus && hasCrossedIssueTabs
    }

    func shouldReleaseBacklogSlot(
        for issueNumber: Int,
        in lane: AssignedIssueLane
    ) -> Bool {
        self.issueNumber == issueNumber
            && sourceLane == lane
            && lane != .focus
            && hasCrossedIssueTabs
    }

    var backlogPreviewKey: RunwayIssueCardKey? {
        guard let backlogPreviewLane else { return nil }
        return RunwayIssueCardKey(
            lane: backlogPreviewLane,
            issueNumber: backlogPreviewTargetIssueNumber ?? -1
        )
    }

    func updateBacklogPreview(
        lane: AssignedIssueLane?,
        before targetIssueNumber: Int?
    ) {
        backlogPreviewLane = lane
        backlogPreviewTargetIssueNumber = targetIssueNumber
    }

    func clearBacklogPreview() {
        backlogPreviewLane = nil
        backlogPreviewTargetIssueNumber = nil
    }

    func shouldInsertBacklogPlaceholder(
        before issueNumber: Int,
        in lane: AssignedIssueLane
    ) -> Bool {
        backlogPreviewLane == lane && backlogPreviewTargetIssueNumber == issueNumber
    }

    func shouldAppendBacklogPlaceholder(in lane: AssignedIssueLane) -> Bool {
        backlogPreviewLane == lane && backlogPreviewTargetIssueNumber == nil
    }

    func lane(at point: CGPoint) -> AssignedIssueLane? {
        laneFrames.first { _, frame in frame.contains(point) }?.key
    }

    func proposedLane(
        at point: CGPoint,
        fallback: AssignedIssueLane,
        displayedBacklogLane: AssignedIssueLane
    ) -> AssignedIssueLane {
        if let lane = lane(at: point) { return lane }
        guard hasCrossedIssueTabs else { return fallback }
        return sourceLane == .focus ? displayedBacklogLane : .focus
    }

    func targetIssue(
        at point: CGPoint,
        in lane: AssignedIssueLane,
        excluding issueNumber: Int
    ) -> Int? {
        cardFrames.first { key, frame in
            key.lane == lane && key.issueNumber != issueNumber && frame.contains(point)
        }?.key.issueNumber
    }

    func insertionTarget(
        at point: CGPoint,
        in lane: AssignedIssueLane,
        excluding issueNumber: Int
    ) -> Int? {
        cardFrames
            .filter { key, frame in
                key.lane == lane && key.issueNumber != issueNumber && !frame.isEmpty
            }
            .sorted { $0.value.minY < $1.value.minY }
            .first { _, frame in point.y < frame.midY }?
            .key.issueNumber
    }

    func shouldMove(to issueNumber: Int) -> Bool {
        guard lastTargetIssueNumber != issueNumber else { return false }
        lastTargetIssueNumber = issueNumber
        return true
    }

    func clearTarget() {
        lastTargetIssueNumber = nil
    }

    func prepareLanding() {
        isLanding = true
        clearBacklogPreview()
        clearFocusPreview()
    }

    func land(at origin: CGPoint) {
        visualOrigin = origin
    }

    func landingFrame(for lane: AssignedIssueLane) -> CGRect {
        guard let destination = frame(for: issueNumber ?? -1, in: lane),
              !destination.isEmpty else { return startingFrame }
        return destination
    }

    func reset() {
        issueNumber = nil
        visualOrigin = .zero
        visualSize = .zero
        sourceLane = nil
        startingFrame = .zero
        crossingBoundaryY = nil
        hasCrossedIssueTabs = false
        backlogPreviewLane = nil
        backlogPreviewTargetIssueNumber = nil
        focusPreviewTargetIssueNumber = nil
        isFocusPreviewActive = false
        grabOffset = .zero
        lastTargetIssueNumber = nil
        isLanding = false
    }
}
