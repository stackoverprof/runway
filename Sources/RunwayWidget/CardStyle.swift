import SwiftUI

/// The one card in Runway.
///
/// A feed row, a flight ticket and anything else that sits in a list are the
/// same object: a near-black panel with a hairline round it that lifts a
/// little under the pointer. The ticket had its own lighter grey and no
/// border at all, so two cards in the same column read as two materials.
/// Both sides read these, so changing a card changes every card.
@MainActor
enum RunwayCard {
    static let radius: CGFloat = 10

    /// Near black, a shade up under the pointer, a shade up again for the
    /// one the rest of the window is answering for.
    static func fill(hovering: Bool = false, selected: Bool = false) -> Color {
        if selected { return Color(white: hovering ? 0.125 : 0.11) }
        return Color(white: hovering ? 0.09 : 0.075)
    }

    /// A hairline, not a frame: visible enough to separate two cards on
    /// black, quiet enough to disappear while you read.
    static func border(hovering: Bool = false, selected: Bool = false) -> Color {
        if selected { return Color.white.opacity(hovering ? 0.22 : 0.16) }
        return Color.white.opacity(hovering ? 0.16 : 0.06)
    }
}
