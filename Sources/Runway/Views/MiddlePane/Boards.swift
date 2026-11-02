import AppKit
import SwiftUI

/// The departures-board look, as the pieces every tab is built from.
///
/// The flight card in the left pane taught the pane its vocabulary: a dark
/// sheet, a letter-spaced bar across the top, columns, and rows you read
/// down. This is that vocabulary for the middle pane, so Issue, Pulls,
/// Walkthrough and Thread are four arrangements of one thing rather than
/// four designs.
///
/// Only what sits on the card is restyled. The card's own grey and the wash
/// of the flight's colour at its head and foot are left exactly as they are.
@MainActor
enum Board {
    static let sheet = Color(red: 0.020, green: 0.020, blue: 0.024)   // #050506
    static let alt = Color(red: 0.039, green: 0.039, blue: 0.043)     // #0a0a0b
    static let bar = Color(red: 0.063, green: 0.067, blue: 0.075)     // #101113
    static let rule = Color(red: 0.106, green: 0.110, blue: 0.118)    // #1b1c1e
    static let row = Color(red: 0.078, green: 0.082, blue: 0.086)     // #141516
    static let hover = Color(red: 0.071, green: 0.075, blue: 0.082)   // #121315
    static let line = Color(red: 0.180, green: 0.188, blue: 0.200)    // #2e3033
    static let ink = Color(red: 0.945, green: 0.945, blue: 0.933)     // #f1f1ee
    static let text = Color(red: 0.788, green: 0.788, blue: 0.773)    // #c9c9c5
    static let muted = Color(red: 0.541, green: 0.549, blue: 0.565)   // #8a8c90
    static let dim = Color(red: 0.416, green: 0.424, blue: 0.439)     // #6a6c70
    static let faint = Color(red: 0.310, green: 0.318, blue: 0.333)   // #4f5155
    static let teal = Color(red: 0.486, green: 0.776, blue: 0.722)    // #7cc6b8
    static let purple = Color(red: 0.663, green: 0.545, blue: 0.941)  // #a98bf0
    static let amber = Color(red: 0.890, green: 0.702, blue: 0.255)   // #e3b341
    static let seatLive = Color(red: 0.373, green: 0.812, blue: 0.478) // #5fcf7a

    /// The frosted box lets the card's own grey and the flight's colour
    /// through, so every surface drawn on it has to be a veil rather than a
    /// colour. A solid bar or a solid band would punch an opaque rectangle
    /// through the glass and the frost would stop at it.
    static let veilBar = Color.white.opacity(0.055)
    static let veilBand = Color.white.opacity(0.022)
    static let veilHover = Color.white.opacity(0.075)
    static let veilDay = Color.black.opacity(0.22)
    /// The strip along the floor of the box is darker than the body above
    /// it, the whole strip and not only the open face: it is the base the
    /// board stands on, and a lighter band under a dark board reads as a
    /// shelf pushed in front of it.
    static let veilFloor = Color.black.opacity(0.34)
    /// Darker again for the face you are on, which is the one you have cut
    /// down to.
    static let veilActive = Color.black.opacity(0.30)
    static let veilTint = Color.black.opacity(0.42)

    static let radius: CGFloat = 10
    static let gutter: CGFloat = 12
}

/// One sheet: a bar, then whatever is stacked under it.
///
/// No border and no corners of its own. The pane is a single black box and
/// every board is a section inside it, told apart by its own bar rather than
/// by a frame: boxes inside a box read as clutter, and the outer one has to
/// hold the floor whether there are three rows on it or thirty.
struct BoardSheet<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content }
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The one box: everything you read about a flight, with the four faces
/// anchored along its floor.
struct BoardBox<Content: View, Tabs: View>: View {
    @ViewBuilder var content: Content
    @ViewBuilder var tabs: Tabs

    var body: some View {
        VStack(spacing: 0) {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            tabs
                .overlay(alignment: .top) { Rectangle().fill(Board.rule).frame(height: 1) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Frosted, not solid. The card's grey and the wash of the flight's
        // colour carry on behind the box instead of stopping at its edge,
        // which is what made a long empty board read as a black hole in the
        // middle of the pane. A dark veil over the material keeps the type
        // on it as legible as it was on black.
        .background(Board.veilTint)
        .background(.ultraThinMaterial)
        .environment(\.colorScheme, .dark)
        .clipShape(RoundedRectangle(cornerRadius: Board.radius))
        .overlay(
            RoundedRectangle(cornerRadius: Board.radius)
                .stroke(Board.rule, lineWidth: 1)
        )
    }
}

/// The bar across the top of a sheet: what this board is, and a figure or a
/// button at the far end.
struct BoardBar<Trailing: View>: View {
    let title: String
    /// A dot before the title, in whatever the figure is coloured.
    var dot: Color?
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 8) {
            if let dot {
                Circle().fill(dot).frame(width: 5, height: 5)
            }
            Text(title.uppercased())
                .font(.mono(7.5, .semibold))
                .tracking(1.8)
                .foregroundStyle(Board.muted)
            Spacer(minLength: 8)
            trailing
        }
        .padding(.horizontal, Board.gutter)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Board.veilBar)
    }
}

extension BoardBar where Trailing == EmptyView {
    init(_ title: String, dot: Color? = nil) {
        self.init(title: title, dot: dot) { EmptyView() }
    }
}

/// The small letter-spaced figure a bar carries at its end.
struct BoardTally: View {
    let text: String
    var colour: Color = Board.faint

    var body: some View {
        Text(text.uppercased())
            .font(.mono(7.5))
            .tracking(1.6)
            .foregroundStyle(colour)
            .fixedSize()
    }
}

/// The column heads under a bar.
struct BoardColumns: View {
    let names: [String]
    let widths: [CGFloat?]

    var body: some View {
        HStack(spacing: 10) {
            ForEach(Array(names.enumerated()), id: \.offset) { index, name in
                Text(name.uppercased())
                    .font(.mono(7))
                    .tracking(1.8)
                    .foregroundStyle(Board.faint)
                    .frame(
                        width: widths[safe: index].flatMap { $0 },
                        alignment: index == names.count - 1 ? .trailing : .leading
                    )
                    .frame(
                        maxWidth: widths[safe: index].flatMap { $0 } == nil ? .infinity : nil,
                        alignment: .leading
                    )
            }
        }
        .padding(.horizontal, Board.gutter)
        .padding(.vertical, 6)
        .background(Board.veilBar)
        .overlay(alignment: .bottom) { Rectangle().fill(Board.row).frame(height: 1) }
    }
}

/// A row on a sheet: banded, lit under the pointer, ruled off from the one
/// above.
struct BoardRow<Content: View>: View {
    var index: Int
    var ruled: Bool = true
    var action: (() -> Void)?
    @ViewBuilder var content: Content
    @State private var hovering = false

    var body: some View {
        content
            .padding(.horizontal, Board.gutter)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(hovering && action != nil ? Board.veilHover : (index.isMultiple(of: 2) ? Color.clear : Board.veilBand))
            .overlay(alignment: .top) {
                if ruled, index > 0 { Rectangle().fill(Board.row).frame(height: 1) }
            }
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
            .modifier(BoardTap(action: action))
    }
}

/// A row is a button only when it has somewhere to go.
private struct BoardTap: ViewModifier {
    let action: (() -> Void)?

    func body(content: Content) -> some View {
        if let action {
            content.onTapGesture(perform: action).pointerCursor()
        } else {
            content
        }
    }
}

/// The button at the foot of a board that asks for the rest.
struct BoardMore: View {
    let title: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Text(title.uppercased())
            .font(.mono(8))
            .tracking(1.6)
            .foregroundStyle(hovering ? Board.ink : Board.muted)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background(hovering ? Board.veilHover : Color.clear)
            .overlay(alignment: .top) { Rectangle().fill(Board.row).frame(height: 1) }
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
            .onTapGesture(perform: action)
            .pointerCursor()
    }
}

/// A small outlined action in a bar, in the board's teal.
struct BoardAction: View {
    let title: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Text(title.uppercased())
            .font(.mono(7.5))
            .tracking(1.6)
            .foregroundStyle(Board.teal)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(hovering ? Color(red: 0.071, green: 0.125, blue: 0.118) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Color(red: 0.122, green: 0.200, blue: 0.188), lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 4))
            .onHover { hovering = $0 }
            .onTapGesture(perform: action)
            .pointerCursor()
    }
}

/// The flap tiles the flight cards wear, reused in the pane's header so the
/// same number reads the same in both places.
struct FlapNumber: View {
    let number: Int
    var size: CGFloat = 11.5

    var body: some View {
        HStack(spacing: 3) {
            ForEach(Array(String(number).enumerated()), id: \.offset) { _, digit in
                FlapTile(digit: digit, size: size)
            }
        }
    }
}

/// One tile of a split-flap board.
///
/// The shading is behind the digit, never over it. An overlay across the
/// whole tile darkened the middle of the glyph as well as the card, and 3,
/// 5, 6 and 8 went muddy exactly where they need their crossbar. So the
/// face carries the fold, the digit stays pure white, and the seam is a
/// single black hairline across the middle.
struct FlapTile: View {
    let digit: Character
    var size: CGFloat = 11.5

    var body: some View {
        Text(String(digit))
            .font(.mono(size, .semibold))
            .foregroundStyle(.white)
            .frame(width: size * 1.14)
            .padding(.vertical, size * 0.26)
            .background(FlapFace.face)
            // The lip of the upper flap catching the light.
            .overlay(alignment: .top) {
                Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1)
            }
            // The seam. One point, across the digit too, the way the two
            // halves of a real flap meet.
            .overlay {
                Rectangle().fill(Color.black.opacity(0.9)).frame(height: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: 4))
            // A black edge, and 3 points between tiles so two edges never
            // merge into one thick rule.
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.black, lineWidth: 1))
    }
}

/// The fold shading, held once so the card and the header cannot drift.
@MainActor
enum FlapFace {
    static let face = LinearGradient(
        stops: [
            .init(color: Color(red: 0.149, green: 0.153, blue: 0.165), location: 0),    // #26272a
            .init(color: Color(red: 0.102, green: 0.106, blue: 0.114), location: 0.49), // #1a1b1d
            .init(color: Color(red: 0.059, green: 0.063, blue: 0.067), location: 0.51), // #0f1011
            .init(color: Color(red: 0.102, green: 0.106, blue: 0.114), location: 1),    // #1a1b1d
        ],
        startPoint: .top, endPoint: .bottom
    )
}

/// One seat in the pilot/copilot switch: a dot, a word, and a pill when it
/// is the one you are reading. No outer box, so the pair sits on the
/// terminal rather than in a control.
struct SeatButton: View {
    let title: String
    let active: Bool
    let dot: Color
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 7) {
            Circle().fill(dot).frame(width: 6, height: 6)
            Text(title.uppercased())
                .font(.mono(8.5, active ? .semibold : .regular))
                .tracking(1.5)
        }
        .foregroundStyle(active ? Board.ink : (hovering ? Board.muted : Board.dim))
        .padding(.horizontal, 11)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(active ? Color(red: 0.090, green: 0.094, blue: 0.102) : .clear)
        )
        .contentShape(RoundedRectangle(cornerRadius: 8))
        .onHover { hovering = $0 }
        .onTapGesture(perform: action)
        .pointerCursor()
    }
}

/// The handle between the terminal and the boards.
struct SplitHandle: View {
    enum Phase { case changed, ended }

    let dragging: Bool
    let onDrag: (CGFloat, Phase) -> Void
    let onReset: () -> Void
    let onStep: (CGFloat) -> Void
    @State private var hovering = false
    @FocusState private var focused: Bool

    var body: some View {
        Capsule()
            .fill(lit ? Board.muted : Color(red: 0.165, green: 0.173, blue: 0.184))
            .frame(width: lit ? 52 : 36, height: 3)
            .animation(.easeOut(duration: 0.15), value: lit)
            .frame(maxWidth: .infinity)
            // The band is the gap, so it carries the whole gap: the bar sits
            // in the middle of it and the terminal above and the board below
            // get the same air.
            .frame(height: 18)
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
            .onContinuousHover { phase in
                if case .active = phase { NSCursor.resizeUpDown.set() } else { NSCursor.arrow.set() }
            }
            .gesture(
                // Global, not local: a local drag measures against the
                // handle itself, and the handle moves as you drag it, so the
                // reading feeds back into the next frame and the pane shakes.
                DragGesture(coordinateSpace: .global)
                    .onChanged { onDrag($0.translation.height, .changed) }
                    .onEnded { _ in onDrag(0, .ended) }
            )
            .onTapGesture(count: 2, perform: onReset)
            .focusable()
            .focused($focused)
            // Arrow keys yes, system focus ring no: a blue rectangle across
            // the whole pane is louder than the handle it marks.
            .focusEffectDisabled()
            .onKeyPress(.upArrow) { onStep(-16); return .handled }
            .onKeyPress(.downArrow) { onStep(16); return .handled }
            .help("Drag to resize the terminal, double-click to reset")
    }

    /// Lit only while the pointer is on it or you are dragging it. Focus is
    /// deliberately left out: clicking the handle gives it focus and keeps
    /// it, so a focused handle stayed bright long after the pointer had gone
    /// and read as a control stuck on.
    private var lit: Bool { hovering || dragging }
}

/// One face in the strip along the floor of the box.
struct SectionTab: View {
    let title: String
    let count: Int?
    let active: Bool
    let first: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 5) {
            Text(title.uppercased())
                .font(.mono(8.5, active ? .semibold : .regular))
                .tracking(1.4)
            if let count {
                Text(verbatim: "\(count)")
                    .font(.mono(7.5))
                    .foregroundStyle(active ? Board.muted : Board.faint)
            }
        }
        .foregroundStyle(active ? Board.ink : (hovering ? Board.muted : Board.dim))
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity)
        .background(active ? Board.veilActive : Color.clear)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(active ? Board.ink : Color.clear)
                .frame(height: 2)
        }
        .overlay(alignment: .leading) {
            if !first { Rectangle().fill(Board.rule).frame(width: 1) }
        }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture(perform: action)
        .pointerCursor()
    }
}

/// A channel the flight is talked about in.
struct ChannelChip: View {
    let name: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "arrow.up.forward.square")
                .font(.system(size: 8.5))
            Text(name)
                .font(.mono(9))
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .foregroundStyle(Board.teal)
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(hovering
                      ? Color(red: 0.078, green: 0.145, blue: 0.133)
                      : Color(red: 0.063, green: 0.110, blue: 0.102))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 5)
                .stroke(Color(red: 0.110, green: 0.180, blue: 0.169), lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 5))
        .onHover { hovering = $0 }
        .onTapGesture(perform: action)
        .pointerCursor()
        .help("Open \(name)")
    }
}
