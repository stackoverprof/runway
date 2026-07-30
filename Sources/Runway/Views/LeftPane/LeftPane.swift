import SwiftUI
import AppKit

/// Left pane: a "working now" presence strip on top, then the activity stream.
struct LeftPane: View {
    @Bindable var ws: Workspace
    @Bindable var feed: GitHubFeed
    @Bindable var agentFeed: AgentFeed
    @State private var showRepoPicker = false
    @State private var showAllPresence = false
    @State private var showNoteComposer = false
    @State private var assignedIssues = AssignedIssues()
    @State private var focusIssueDrag = FocusIssueDrag()
    @State private var runwayIssueTab: RunwayIssueTab = .open
    @State private var showMergesOnly = false
    @State private var issueSearchVisible = false
    @State private var issueSearchQuery = ""
    @State private var feedSearchVisible = false
    @State private var feedSearchQuery = ""
    @State private var postSearchVisible = false
    @State private var postSearchQuery = ""
    @FocusState private var focusedSearchTab: FeedTab?
    @AppStorage(SettingsKey.fireThreshold) private var fireThreshold = 5
    @AppStorage(SettingsKey.brandHeaderStyle) private var brandHeaderStyle = "text"
    @AppStorage(SettingsKey.brandTitle) private var brandTitle = "Activity"
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
        }
        .coordinateSpace(name: FocusIssueDrag.coordinateSpaceName)
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
        }
        .onChange(of: ws.selectedTab) { previousTab, tab in
            closeEmptySearch(for: previousTab)
            focusedSearchTab = nil
            if tab == .feeds {
                Task { await feed.refresh() }
            }
        }
        .onChange(of: ws.findRequestID) { _, _ in
            toggleSearch(for: ws.selectedTab)
        }
        .task(id: emptySearchIsOpen(for: .runway)) {
            await closeSearchAfterIdle(for: .runway)
        }
        .task(id: emptySearchIsOpen(for: .feeds)) {
            await closeSearchAfterIdle(for: .feeds)
        }
        .task(id: emptySearchIsOpen(for: .posts)) {
            await closeSearchAfterIdle(for: .posts)
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
        HStack(alignment: .center, spacing: 8) {
            brandingTitle
            Spacer(minLength: 8)
            repoButton
        }
        .padding(.horizontal, 16)
        // Clear the traffic lights when windowed; tighten to the top in full screen.
        .padding(.top, ws.isFullScreen ? 18 : 50)
        .padding(.bottom, 22)
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

    private var tabIndex: Int {
        switch ws.selectedTab {
        case .runway: return 0
        case .feeds: return 1
        case .posts: return 2
        }
    }

    private var subHeader: some View {
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
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .onAppear {
            if displayedTagline.isEmpty {
                displayedTagline = Self.taglines[taglineIndex]
                lastEventCount = feed.events.count
            }
        }
        .onChange(of: feed.events.count) { old, new in
            guard ws.selectedTab == .feeds, new > old, !isTyping else { return }
            rotateTagline()
        }
    }

    private var subHeaderText: String {
        switch ws.selectedTab {
        case .runway: "ON TODAY'S MISSIONS"
        case .feeds: displayedTagline
        case .posts: "FROM THE LOGBOOK"
        }
    }

    private var slidingTabContent: some View {
        GeometryReader { geo in
            HStack(spacing: 0) {
                // Runway tab
                runwayTab
                    .frame(width: geo.size.width)

                // Feeds tab, optionally filtered to merged pull requests only.
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
                                let sourceItems = showMergesOnly
                                    ? agentFeed.mergeTimeline(github: feed.events)
                                    : agentFeed.timeline(github: feed.events)
                                let items = filteredTimeline(
                                    sourceItems,
                                    query: feedSearchQuery,
                                    isSearching: feedSearchVisible
                                )
                                if items.isEmpty {
                                    if feedSearchVisible,
                                       !feedSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                        searchEmptyPlaceholder("No matching feed activity")
                                    } else if showMergesOnly {
                                        mergeEmptyPlaceholder
                                    } else {
                                        emptyTabPlaceholder(for: .feeds)
                                    }
                                } else {
                                    ForEach(items) { entry in
                                        renderEntry(entry, isLast: entry.id == items.last?.id)
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
                .frame(width: geo.size.width)

                // Notes tab
                VStack(spacing: 0) {
                    if postSearchVisible {
                        searchField(
                            placeholder: "Search notes",
                            text: $postSearchQuery,
                            tab: .posts
                        )
                        .padding(.horizontal, 16)
                        .padding(.bottom, 12)
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }

                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            postNoteButton
                            if showNoteComposer {
                                NoteComposer(isPresented: $showNoteComposer) { body in
                                    agentFeed.createNote(body: body)
                                }
                                .padding(.bottom, 14)
                                .transition(.opacity.combined(with: .move(edge: .top)))
                            }

                            let pinnedItems = filteredTimeline(
                                agentFeed.pinnedPostsTimeline(),
                                query: postSearchQuery,
                                isSearching: postSearchVisible
                            )
                            if !pinnedItems.isEmpty {
                                VStack(alignment: .leading, spacing: 0) {
                                    ForEach(pinnedItems) { entry in
                                        renderEntry(entry, isLast: entry.id == pinnedItems.last?.id)
                                    }

                                    Rectangle()
                                        .fill(Color.white.opacity(0.06))
                                        .frame(height: 1)
                                        .padding(.top, 2)
                                        .padding(.bottom, 8)
                                }
                                .padding(.top, 10)
                            }

                            let items = filteredTimeline(
                                agentFeed.postsTimeline(),
                                query: postSearchQuery,
                                isSearching: postSearchVisible
                            )
                            if items.isEmpty && pinnedItems.isEmpty {
                                if postSearchVisible,
                                   !postSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                    searchEmptyPlaceholder("No matching notes")
                                } else {
                                    emptyTabPlaceholder(for: .posts)
                                }
                            } else {
                                ForEach(items) { entry in
                                    renderEntry(entry, isLast: entry.id == items.last?.id)
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 16)
                    }
                    .contentMargins(.top, 0, for: .scrollContent)
                    .scrollIndicators(.hidden)
                }
                .frame(width: geo.size.width)
            }
            .offset(x: -CGFloat(tabIndex) * geo.size.width)
            .animation(.spring(response: 0.38, dampingFraction: 0.85), value: ws.selectedTab)
        }
    }

    private enum RunwayIssueTab: String, CaseIterable {
        case open = "Open"
        case closed = "Closed"
    }

    private var runwayTab: some View {
        VStack(alignment: .leading, spacing: 0) {
            runwayEmptyContainer
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
                .layoutPriority(2)

            runwayBacklog
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .clipped()
        }
        .animation(.spring(response: 0.38, dampingFraction: 0.85), value: runwayIssueTab)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .clipped()
        .task(id: feed.repo) {
            assignedIssues.restore(repository: feed.repo)
            syncFocusBoard()
            await assignedIssues.revalidate(repository: feed.repo)
            syncFocusBoard()
        }
        .task(id: ws.selectedTab) {
            guard ws.selectedTab == .runway else { return }
            while !Task.isCancelled {
                await assignedIssues.revalidate(
                    repository: feed.repo,
                    minimumAge: 15
                )
                syncFocusBoard()
                try? await Task.sleep(nanoseconds: 30_000_000_000)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            guard ws.selectedTab == .runway else { return }
            revalidateFocusBoard()
        }
        .onChange(of: assignedIssues.focusedIssueNumbers) { _, _ in
            guard focusIssueDrag.issueNumber == nil else { return }
            syncFocusBoard()
        }
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
                .padding(.bottom, 12)

            if assignedIssues.loading && assignedIssues.issues.isEmpty {
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = assignedIssues.error, assignedIssues.issues.isEmpty {
                feedNotice(error, systemImage: "exclamationmark.triangle")
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
                        value: runwayIssueTab
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
                        repository: issueRepositoryName
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
                    .contextMenu {
                        Button("Remove from focus") {
                            assignedIssues.removeFromFocus(issueNumber: issue.number)
                        }
                    }
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

            let hoveredLane = focusIssueDrag.lane(at: value.location)
            if lane == .focus, focusIssueDrag.isCrossingIssueTabs {
                let displayedLane: AssignedIssueLane = runwayIssueTab == .open ? .open : .closed
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
            guard focusIssueDrag.issueNumber == issue.number,
                  let sourceLane = focusIssueDrag.sourceLane else { return }
            let proposedLane = focusIssueDrag.proposedLane(
                at: value.location,
                fallback: sourceLane,
                displayedBacklogLane: runwayIssueTab == .open ? .open : .closed
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
                    withAnimation(.easeInOut(duration: 0.15)) { runwayIssueTab = tab }
                } label: {
                    HStack(spacing: 5) {
                        Text(tab.rawValue)
                        Text("\(assignedIssueCount(for: tab))")
                            .foregroundStyle(Color.white.opacity(0.35))
                    }
                    .font(.system(size: 10.5, weight: runwayIssueTab == tab ? .semibold : .medium))
                    .foregroundStyle(runwayIssueTab == tab ? Color.white.opacity(0.9) : Color.white.opacity(0.4))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .frame(maxWidth: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(runwayIssueTab == tab ? Color.white.opacity(0.1) : Color.clear)
                    )
                    .contentShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .onHover { hovering in
                    if hovering { NSCursor.pointingHand.set() } else { NSCursor.arrow.set() }
                }
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
                if willShow {
                    runwayIssueTab = .open
                } else {
                    issueSearchQuery = ""
                    runwayIssueTab = .open
                }
            case .feeds:
                feedSearchVisible.toggle()
                willShow = feedSearchVisible
                if !willShow { feedSearchQuery = "" }
            case .posts:
                postSearchVisible.toggle()
                willShow = postSearchVisible
                if !willShow { postSearchQuery = "" }
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
        case .posts:
            return postSearchVisible
                && postSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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
                runwayIssueTab = .open
            case .feeds:
                feedSearchVisible = false
                feedSearchQuery = ""
            case .posts:
                postSearchVisible = false
                postSearchQuery = ""
            }
        }
        if focusedSearchTab == tab {
            focusedSearchTab = nil
        }
    }

    private func filteredTimeline(
        _ entries: [TimelineEntry],
        query: String,
        isSearching: Bool
    ) -> [TimelineEntry] {
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isSearching, !normalized.isEmpty else { return entries }
        return entries.filter {
            timelineSearchText($0).localizedCaseInsensitiveContains(normalized)
        }
    }

    private func timelineSearchText(_ entry: TimelineEntry) -> String {
        switch entry {
        case let .github(event):
            let actor = "\(event.actor) \(PersonProfileManager.shared.displayName(for: event.actor))"
            let detail: String
            switch event.kind {
            case let .push(branch, count, commits):
                detail = "push pushed \(branch) \(count.map(String.init) ?? "") "
                    + commits.map { "\($0.sha) \($0.message)" }.joined(separator: " ")
            case let .prOpened(number, title, branch):
                detail = "pull request pr opened #\(number) \(title) \(branch)"
            case let .prMerged(number, title, base, branch, additions, deletions, commits, _):
                detail = "pull request pr merged merge #\(number) \(title) \(base) \(branch) "
                    + "\(additions.map(String.init) ?? "") \(deletions.map(String.init) ?? "") "
                    + "\(commits.map(String.init) ?? "")"
            case let .branchCreated(name):
                detail = "branch created \(name)"
            case let .branchDeleted(name):
                detail = "branch deleted \(name)"
            case let .review(number, title, state):
                detail = "review reviewed pull request pr #\(number) \(title) \(state)"
            case let .issueOpened(number, title):
                detail = "issue opened open #\(number) \(title)"
            case let .issueClosed(number, title):
                detail = "issue closed close #\(number) \(title)"
            }
            return "\(actor) \(detail)"
        case let .agent(post):
            return "\(post.author) \(PersonProfileManager.shared.displayName(for: post.author)) "
                + "\(post.title ?? "") \(post.body)"
        case let .userNote(note):
            return note.body
        }
    }

    private func runwayIssueList(
        _ issues: [AssignedIssue],
        lane: AssignedIssueLane
    ) -> some View {
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
                        repository: issueRepositoryName
                    )
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
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
        .contentMargins(.top, 0, for: .scrollContent)
        .scrollIndicators(.hidden)
        .background {
            GeometryReader { proxy in
                Color.clear.preference(
                    key: RunwayIssueLaneFramePreferenceKey.self,
                    value: [lane: proxy.frame(in: .named(FocusIssueDrag.coordinateSpaceName))]
                )
            }
        }
    }

    private var runwayIssueTabIndex: Int {
        runwayIssueTab == .open ? 0 : 1
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
        return issues.filter { issue in
            "#\(issue.number) \(issue.title) \(issueRepositoryName)"
                .localizedCaseInsensitiveContains(query)
        }
    }

    private func updateIssueSearchTab() {
        guard issueSearchVisible else { return }
        let query = issueSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let preferredTab: RunwayIssueTab = !query.isEmpty
            && filteredOpenIssues.isEmpty
            && !filteredClosedIssues.isEmpty
            ? .closed
            : .open
        guard runwayIssueTab != preferredTab else { return }
        withAnimation(.easeInOut(duration: 0.15)) {
            runwayIssueTab = preferredTab
        }
    }

    private var issueRepositoryName: String {
        feed.repo.split(separator: "/").last.map(String.init) ?? feed.repo
    }

    private func syncFocusBoard() {
        guard assignedIssues.hasSnapshot else { return }
        ws.syncFocusBoard(issues: assignedIssues.focused, repository: feed.repo)
    }

    private func revalidateFocusBoard() {
        Task {
            await assignedIssues.revalidate(
                repository: feed.repo,
                minimumAge: 15
            )
            syncFocusBoard()
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
        }
        .contentMargins(.top, 0, for: .scrollContent)
        .scrollIndicators(.hidden)
        .coordinateSpace(name: "feed")
    }

    @ViewBuilder private func renderEntry(_ entry: TimelineEntry, isLast: Bool) -> some View {
        switch entry {
        case let .github(event):
            FeedRow(event: event, time: clock(event.date),
                    isLast: isLast, repo: feed.repo)
                .transition(.move(edge: .top).combined(with: .opacity))
        case let .agent(post):
            AgentFeedRow(post: post, time: clock(post.date),
                         isLast: isLast,
                         agentFeed: agentFeed)
                .transition(.move(edge: .top).combined(with: .opacity))
        case let .userNote(note):
            UserNoteRow(note: note, time: clock(note.date),
                        isLast: isLast,
                        agentFeed: agentFeed)
                .transition(.move(edge: .top).combined(with: .opacity))
        }
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

    // MARK: Post a Note button
    private var postNoteButton: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) { showNoteComposer.toggle() }
        } label: {
            HStack(spacing: 7) {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 11, weight: .medium))
                Text("Post a Note")
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(Color(red: 0.45, green: 0.82, blue: 0.78))
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color(red: 0.45, green: 0.82, blue: 0.78).opacity(0.08)))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(red: 0.45, green: 0.82, blue: 0.78).opacity(0.15), lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .onHover { if $0 { NSCursor.pointingHand.set() } else { NSCursor.arrow.set() } }
        .padding(.bottom, 6)
    }

    // MARK: Empty tab placeholder
    @ViewBuilder private func emptyTabPlaceholder(for tab: FeedTab) -> some View {
        switch tab {
        case .runway:
            EmptyView()
        case .feeds:
            placeholderCard(icon: "tray", title: "No activity yet",
                            subtitle: "Events from your team will appear here as they happen.")
        case .posts:
            placeholderCard(icon: "sparkles", title: "Notes will appear here",
                            subtitle: "Your agents can be automated to post updates here for any of your needs — build reports, deployment status, daily recaps, and more.\n\nYou can also post your own notes above.")
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
                showMergesOnly.toggle()
            }
        } label: {
            HStack(spacing: 9) {
                ZStack {
                    RoundedRectangle(cornerRadius: 3.5)
                        .fill(
                            showMergesOnly
                                ? Color(red: 0.45, green: 0.82, blue: 0.78)
                                : Color.clear
                        )
                    RoundedRectangle(cornerRadius: 3.5)
                        .stroke(
                            showMergesOnly
                                ? Color(red: 0.45, green: 0.82, blue: 0.78)
                                : Color.white.opacity(0.55),
                            lineWidth: 1.5
                        )
                    if showMergesOnly {
                        Image(systemName: "checkmark")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(Color.black.opacity(0.75))
                    }
                }
                .frame(width: 14, height: 14)
                Text("Show Merge")
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
        .onHover { hovering in
            if hovering { NSCursor.pointingHand.set() } else { NSCursor.arrow.set() }
        }
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
                    withAnimation(.easeInOut(duration: 0.15)) { ws.selectedTab = tab }
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
                .onHover { if $0 { NSCursor.pointingHand.set() } else { NSCursor.arrow.set() } }
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

    private func rotateTagline() {
        isTyping = true
        // Fade out
        withAnimation(.easeOut(duration: 0.25)) { taglineOpacity = 0 }
        // After fade out, pick next tagline and type it in
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            taglineIndex = (taglineIndex + 1) % Self.taglines.count
            let target = Self.taglines[taglineIndex]
            displayedTagline = ""
            taglineOpacity = 1.0
            typeIn(target, at: 0)
        }
    }

    private func typeIn(_ target: String, at index: Int) {
        guard index < target.count else {
            isTyping = false
            return
        }
        let charIndex = target.index(target.startIndex, offsetBy: index)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.025) {
            displayedTagline.append(target[charIndex])
            typeIn(target, at: index + 1)
        }
    }
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
        cardFrames = frames
    }

    func updateLaneFrames(_ frames: [AssignedIssueLane: CGRect]) {
        laneFrames = frames
    }

    func updateIssueTabsFrame(_ frame: CGRect) {
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
