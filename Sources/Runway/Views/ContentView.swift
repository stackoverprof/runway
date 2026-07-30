import SwiftUI

struct ContentView: View {
    @State private var context = RunwayWindowContext()
    // Keeps the rotating activity label and all four tabs usable on one line.
    private let minLeft: CGFloat = 440
    private let minRight: CGFloat = 320

    var body: some View {
        GeometryReader { geo in
            let total = geo.size.width
            let maxLeft = max(minLeft, total - minRight)
            let left = min(max(context.workspace.leftWidth, minLeft), maxLeft)

            ZStack(alignment: .bottomLeading) {
                HStack(spacing: 0) {
                    LeftPane(ws: context.workspace, feed: context.githubFeed)
                        .frame(width: left)
                        .zIndex(context.workspace.isFocusCardDragging ? 2 : 0)

                    Rectangle()
                        .fill(Color.white.opacity(0.07))
                        .frame(width: 1)
                        .overlay(
                            Rectangle()
                                .fill(.clear)
                                .frame(width: 12)          // wider invisible hit target
                                .contentShape(Rectangle())
                                .onHover { hovering in
                                    if hovering { NSCursor.resizeLeftRight.set() }
                                    else { NSCursor.arrow.set() }
                                }
                                .gesture(
                                    DragGesture(coordinateSpace: .named("split"))
                                        .onChanged { value in
                                            context.workspace.leftWidth = min(max(value.location.x, minLeft), maxLeft)
                                        }
                                )
                        )

                    RightPane(ws: context.workspace)    // right: scrollable boxes + add button
                        .frame(maxWidth: .infinity)
                }
                .frame(maxHeight: .infinity)
                .coordinateSpace(name: "split")

                // Always mounted (so its shell keeps running); slides in/out with ⌘⌥Q.
                QuickTerminal(ws: context.workspace, width: left, availableHeight: geo.size.height)
            }
        }
        .ignoresSafeArea()
        .background(WindowConfigurator())
        .background(WindowRegistrationView(context: context))
        .onAppear { context.startIfNeeded() }
        .onDisappear { context.stop() }
    }
}
