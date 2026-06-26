import SwiftUI
import AppKit

/// Transient top-right notifications (offline, agent needs attention, etc.).
@MainActor @Observable final class ToastCenter {
    static let shared = ToastCenter()

    struct Toast: Identifiable {
        let id = UUID()
        let icon: String
        let title: String
        let tint: Color
    }

    private(set) var toasts: [Toast] = []
    private init() {}

    /// Show a toast (auto-dismisses). Optionally play the system alert sound.
    func show(_ title: String, icon: String = "bell.fill", tint: Color = .white, sound: Bool = false) {
        let toast = Toast(icon: icon, title: title, tint: tint)
        withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) { toasts.append(toast) }
        if sound { Self.playAlert() }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 4_500_000_000)
            dismiss(toast.id)
        }
    }

    func dismiss(_ id: UUID) {
        withAnimation(.easeOut(duration: 0.2)) { toasts.removeAll { $0.id == id } }
    }

    private static func playAlert() {
        if let sound = NSSound(named: "Glass") ?? NSSound(named: "Ping") {
            sound.play()
        } else {
            NSSound.beep()
        }
    }
}

/// Stacked toasts pinned to the top-right of the window.
struct ToastOverlay: View {
    @Bindable private var center = ToastCenter.shared

    var body: some View {
        VStack(alignment: .trailing, spacing: 8) {
            ForEach(center.toasts) { toast in
                HStack(spacing: 9) {
                    Image(systemName: toast.icon)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(toast.tint)
                    Text(toast.title)
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.92))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 13)
                .padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color(white: 0.14)))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.12), lineWidth: 1))
                .shadow(color: .black.opacity(0.45), radius: 14, y: 5)
                .contentShape(RoundedRectangle(cornerRadius: 10))
                .onTapGesture { center.dismiss(toast.id) }
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .frame(maxWidth: 300, alignment: .trailing)
        .padding(.top, 14)
        .padding(.trailing, 14)
    }
}
