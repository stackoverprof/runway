import SwiftUI

/// Lays its children left to right, wrapping when the line runs out.
///
/// A flight can name half a dozen channels. An `HStack` would squeeze them
/// until each is unreadable; this gives every one its natural width and
/// starts a new line instead.
struct FlowRow: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var line: CGFloat = 0
        var height: CGFloat = 0
        var lineHeight: CGFloat = 0
        for size in subviews.map({ $0.sizeThatFits(.unspecified) }) {
            if line > 0, line + spacing + size.width > width {
                height += lineHeight + spacing
                line = 0
                lineHeight = 0
            }
            line += (line > 0 ? spacing : 0) + size.width
            lineHeight = max(lineHeight, size.height)
        }
        return CGSize(width: proposal.width ?? line, height: height + lineHeight)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        var x = bounds.minX
        var y = bounds.minY
        var lineHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += lineHeight + spacing
                lineHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}
