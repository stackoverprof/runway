import SwiftUI

/// A softly pulsing placeholder block (bar or circle), used during initial load.
struct SkeletonShape: View {
    enum Kind { case bar, circle }
    let kind: Kind
    @State private var pulse = false
    init(_ kind: Kind = .bar) { self.kind = kind }

    var body: some View {
        Group {
            switch kind {
            case .circle: Circle().fill(fill)
            case .bar: RoundedRectangle(cornerRadius: 4).fill(fill)
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.95).repeatForever(autoreverses: true)) { pulse = true }
        }
    }
    private var fill: Color { Color.white.opacity(pulse ? 0.11 : 0.045) }
}

/// A skeleton timeline card matching `FeedRow`'s layout, so real rows replacing
/// these don't shift the surrounding content.
struct SkeletonRow: View {
    let isLast: Bool
    let seed: Int

    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            ZStack(alignment: .top) {
                if !isLast {
                    Rectangle().fill(Color.white.opacity(0.06))
                        .frame(width: 1.5).frame(maxHeight: .infinity)
                }
                // Opaque base so the rail line passes *under* the node (the real
                // avatar is opaque; the skeleton fill alone is translucent).
                SkeletonShape(.circle)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(Color(white: 0.035)))
            }
            .frame(width: 28)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    SkeletonShape().frame(width: 70, height: 12)
                    SkeletonShape().frame(width: 46, height: 12)
                    Spacer(minLength: 6)
                    SkeletonShape().frame(width: 30, height: 10)
                }
                SkeletonShape().frame(width: 120 + CGFloat((seed % 3) * 34), height: 18)
            }
            .padding(11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.02)))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.05), lineWidth: 1))
            .padding(.bottom, 10)
        }
    }
}
