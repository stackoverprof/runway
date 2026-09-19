import SwiftUI

struct ContentView: View {
    @State private var context = RunwayWindowContext()
    @State private var splitDragStartWidth: CGFloat?
    // Keeps the rotating activity label and all four tabs usable on one line.
    private let minLeft: CGFloat = 440
    private let minRight: CGFloat = 320
    /// The divider stays one point wide, but the full gutter accepts the drag.
    private let splitHitWidth: CGFloat = 20
    private let splitLayoutWidth: CGFloat = 1

    var body: some View {
        GeometryReader { geo in
            let total = geo.size.width
            let maxLeft = max(minLeft, total - minRight - splitLayoutWidth)
            let left = min(max(context.workspace.leftWidth, minLeft), maxLeft)

            ZStack(alignment: .bottomLeading) {
                HStack(spacing: 0) {
                    LeftPane(ws: context.workspace, feed: context.githubFeed)
                        .frame(width: left)
                        .zIndex(context.workspace.isFocusCardDragging ? 2 : 0)

                    ZStack {
                        Rectangle()
                            .fill(Color.white.opacity(0.07))
                            .frame(width: 1)
                    }
                    .frame(width: splitHitWidth)
                    .contentShape(Rectangle())
                    // Keep only the hairline in layout. The transparent part
                    // overlaps both panes instead of becoming a visible gutter.
                    .padding(
                        .horizontal,
                        -(splitHitWidth - splitLayoutWidth) / 2
                    )
                    .onHover { hovering in
                        if hovering { NSCursor.resizeLeftRight.set() }
                        else { NSCursor.arrow.set() }
                    }
                    .gesture(
                        DragGesture(coordinateSpace: .named("split"))
                            .onChanged { value in
                                let start = splitDragStartWidth ?? left
                                splitDragStartWidth = start
                                context.workspace.leftWidth = min(
                                    max(start + value.translation.width, minLeft),
                                    maxLeft
                                )
                            }
                            .onEnded { _ in splitDragStartWidth = nil }
                    )
                    .zIndex(3)

                    RightPane(ws: context.workspace)    // right: scrollable boxes + add button
                        .frame(maxWidth: .infinity)
                }
                .frame(maxHeight: .infinity)
                .coordinateSpace(name: "split")

                // Always mounted (so its shell keeps running); slides in/out with ⌘⌥Q.
                QuickTerminal(
                    ws: context.workspace,
                    width: left,
                    availableHeight: geo.size.height,
                    resizePane: { proposedWidth in
                        context.workspace.leftWidth = min(
                            max(proposedWidth, minLeft),
                            maxLeft
                        )
                    }
                )
            }
        }
        .ignoresSafeArea()
        .overlay(alignment: .top) {
            if !context.workspace.isFullScreen {
                WindowDragRegion()
                    .frame(height: WindowChrome.zoomBandHeight)
            }
        }
        // Agents waiting in a repository that is not on screen. Top-trailing:
        // the window controls own the other corner.
        .overlay(alignment: .topTrailing) {
            AttentionBanners(ws: context.workspace)
        }
        .background(WindowConfigurator())
        .background(WindowRegistrationView(context: context))
        .onAppear { context.startIfNeeded() }
        .onDisappear { context.stop() }
    }
}
