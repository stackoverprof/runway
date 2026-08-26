import SwiftUI

/// In-app alerts for agents waiting in a repository that is not on screen.
///
/// A card in the selected repository pulses where the user can see it. A parked
/// one cannot, so it says so here, and clicking it goes straight there.
struct AttentionBanners: View {
    @Bindable var ws: Workspace

    var body: some View {
        VStack(alignment: .trailing, spacing: 8) {
            ForEach(ws.attentionAlerts) { alert in
                banner(alert)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .padding(.top, 12)
        .padding(.trailing, 12)
        .animation(.spring(response: 0.34, dampingFraction: 0.85), value: ws.attentionAlerts)
    }

    private func banner(_ alert: AttentionAlert) -> some View {
        HStack(spacing: 9) {
            Circle()
                .fill(Color(red: 0.91, green: 0.62, blue: 0.20))
                .frame(width: 7, height: 7)
                .shadow(color: Color(red: 0.91, green: 0.62, blue: 0.20).opacity(0.7), radius: 4)

            VStack(alignment: .leading, spacing: 2) {
                Text(shortRepository(alert.repository))
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.45))
                Text("\(alert.title) needs you")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.9))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            Button {
                ws.dismissAttention(alert)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(Color.white.opacity(0.4))
            }
            .buttonStyle(.plain)
            .pointerCursor()
            .help("Dismiss")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .frame(maxWidth: 280, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.black.opacity(0.62))
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color(red: 0.91, green: 0.62, blue: 0.20).opacity(0.35), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.45), radius: 12, y: 4)
        .contentShape(RoundedRectangle(cornerRadius: 10))
        .pointerCursor()
        .onTapGesture { ws.openAttention(alert) }
        .help("Switch to \(alert.repository) and focus this agent")
    }

    private func shortRepository(_ repository: String) -> String {
        repository.split(separator: "/").last.map(String.init) ?? repository
    }
}
