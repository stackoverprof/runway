import SwiftUI

struct ContentView: View {
    @State private var context = RunwayWindowContext()

    var body: some View {
        LeftPane(ws: context.workspace, feed: context.githubFeed)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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
}
