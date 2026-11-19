import SwiftUI

struct FlapNumber: View {
    let number: Int
    var size: CGFloat = 11.5

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Array(String(number).enumerated()), id: \.offset) { _, digit in
                FlapTile(digit: digit, size: size)
            }
        }
    }
}

/// One tile of a split-flap board.
///
/// Two tones meeting at the middle, darker than the card they sit on, and
/// the fold drawn *behind* the digit. Every earlier try put the line over
/// the glyph, and a black rule through the waist of a 3, a 5, a 6 or an 8
/// is exactly where those digits carry their meaning. Here the fold is part
/// of the tile's back and the digit wears a soft halo in the lower tone, so
/// the line visibly stops at each stroke and picks up on the far side, the
/// way it does on a real board.
struct FlapTile: View {
    let digit: Character
    var size: CGFloat = 11.5

    /// The two halves. A hard step at the middle, no blur: the fold is an
    /// edge, not a gradient.
    static let upper = Color(red: 0.063, green: 0.067, blue: 0.075)  // #101113
    static let lower = Color(red: 0.020, green: 0.020, blue: 0.024)  // #050506
    /// The lip of the lower flap catching the light, one point under the
    /// seam. Without it the two halves read as one dark rectangle with a
    /// scratch across it.
    static let lit = Color(red: 0.110, green: 0.114, blue: 0.125)    // #1c1d20

    var body: some View {
        Text(String(digit))
            .font(.mono(size, .semibold))
            .foregroundStyle(.white)
            // The halo that eats the fold where a stroke crosses it. Three
            // passes, one wide and two tight, so the lines stop cleanly
            // without the digit growing a visible outline. It has to be the
            // lower tone exactly, or it shows as a smudge round the glyph.
            .shadow(color: Self.lower, radius: 2)
            .shadow(color: Self.lower, radius: 1)
            .shadow(color: Self.lower, radius: 1)
            .frame(width: size * 1.14)
            .padding(.vertical, size * 0.26)
            .background {
                // All of it behind the text, which is what SwiftUI gives for
                // free: a background is a background, so there is no z-index
                // to get wrong and nothing to isolate.
                ZStack(alignment: .top) {
                    VStack(spacing: 0) {
                        Self.upper
                        Self.lower
                    }
                    GeometryReader { geo in
                        let middle = (geo.size.height / 2).rounded()
                        Rectangle().fill(Color.black)
                            .frame(height: 1)
                            .offset(y: middle)
                        Rectangle().fill(Self.lit)
                            .frame(height: 1)
                            .offset(y: middle + 1)
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}

