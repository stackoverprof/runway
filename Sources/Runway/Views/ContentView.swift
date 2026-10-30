import SwiftUI

struct ContentView: View {
    @State private var context = RunwayWindowContext()
    @State private var dragStartWidth: CGFloat?
    // Keeps the rotating activity label and every tab usable on one line.
    private let minLeft: CGFloat = 440
    private let minMiddle: CGFloat = 280
    private let minRight: CGFloat = 280
    /// Each divider stays one point wide, but the full gutter accepts the drag.
    private let gutter: CGFloat = 20
    private let hairline: CGFloat = 1

    var body: some View {
        GeometryReader { geo in
            let widths = paneWidths(in: geo.size.width)

            ZStack(alignment: .bottomLeading) {
                HStack(spacing: 0) {
                    LeftPane(ws: context.workspace, feed: context.githubFeed)
                        .frame(width: widths.left)

                    divider { translation in
                        let start = dragStartWidth ?? widths.left
                        dragStartWidth = start
                        context.workspace.leftWidth = start + translation
                    }

                    // Open space, waiting for whatever v3 puts here.
                    Color.black
                        .frame(width: widths.middle)

                    divider { translation in
                        let start = dragStartWidth ?? widths.middle
                        dragStartWidth = start
                        context.workspace.middleWidth = start + translation
                    }

                    Color.black
                        .frame(maxWidth: .infinity)
                }
                .frame(maxHeight: .infinity)
                .coordinateSpace(name: "split")

                // Always mounted, so its shell keeps running; slides in and out
                // with ⌘⌥Q.
                QuickTerminal(
                    ws: context.workspace,
                    width: widths.left,
                    availableHeight: geo.size.height,
                    resizePane: { proposed in
                        context.workspace.leftWidth = proposed
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
        .background(WindowConfigurator())
        .background(WindowRegistrationView(context: context))
        .onAppear { context.startIfNeeded() }
        .onDisappear { context.stop() }
    }

    /// Three panes and two hairlines, each pane wide enough to read. The last
    /// one takes what is left, so the window's own width is never over-spent.
    private func paneWidths(in total: CGFloat) -> (left: CGFloat, middle: CGFloat) {
        let free = max(total - hairline * 2, minLeft + minMiddle + minRight)
        let left = min(max(context.workspace.leftWidth, minLeft), free - minMiddle - minRight)
        let middle = min(max(context.workspace.middleWidth, minMiddle), free - left - minRight)
        return (left, middle)
    }

    private func divider(onDrag: @escaping (CGFloat) -> Void) -> some View {
        ZStack {
            Rectangle()
                .fill(Color.white.opacity(0.07))
                .frame(width: hairline)
        }
        .frame(width: gutter)
        .contentShape(Rectangle())
        // Keep only the hairline in layout. The transparent part overlaps the
        // panes instead of becoming a visible gutter.
        .padding(.horizontal, -(gutter - hairline) / 2)
        .onHover { hovering in
            if hovering { NSCursor.resizeLeftRight.set() } else { NSCursor.arrow.set() }
        }
        .gesture(
            DragGesture(coordinateSpace: .named("split"))
                .onChanged { onDrag($0.translation.width) }
                .onEnded { _ in dragStartWidth = nil }
        )
        .zIndex(3)
    }
}
