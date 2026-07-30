import AppKit
import SwiftUI

private struct PointerCursorModifier: ViewModifier {
    let active: Bool
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovering = false
    @State private var didPushCursor = false

    func body(content: Content) -> some View {
        content
            .onHover { hovering in
                isHovering = hovering
                updateCursor(shouldPush: active && hovering && isEnabled)
            }
            .onChange(of: isEnabled) { _, enabled in
                guard isHovering else { return }
                updateCursor(shouldPush: active && enabled)
            }
            .onDisappear {
                updateCursor(shouldPush: false)
            }
    }

    private func updateCursor(shouldPush: Bool) {
        if shouldPush, !didPushCursor {
            NSCursor.pointingHand.push()
            didPushCursor = true
        } else if !shouldPush, didPushCursor {
            NSCursor.pop()
            didPushCursor = false
        }
    }
}

extension View {
    func pointerCursor(_ active: Bool = true) -> some View {
        modifier(PointerCursorModifier(active: active))
    }
}
