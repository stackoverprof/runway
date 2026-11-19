import Foundation

/// Matching for user-typed search text. Ignores case, accents, and width,
/// and spells out letters that are not accented forms (Icelandic þ, ð, æ, ...),
/// so "ksi" finds "KSÍ" and "thor" finds "Þór".
enum SearchText {
    private static let transliterations: [Character: String] = [
        "þ": "th", "ð": "d", "æ": "ae", "ø": "o", "ß": "ss", "œ": "oe", "ł": "l",
    ]

    static func normalized(_ text: String) -> String {
        let folded = text.folding(
            options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
            locale: nil
        )
        guard folded.contains(where: { transliterations[$0] != nil }) else { return folded }
        return folded.reduce(into: "") { result, character in
            if let replacement = transliterations[character] {
                result += replacement
            } else {
                result.append(character)
            }
        }
    }

    /// True when `query`, taken as one phrase, appears in `text`.
    static func contains(_ text: String, _ query: String) -> Bool {
        normalized(text).contains(normalized(query))
    }

    /// True when every whitespace-separated token of `query` appears somewhere
    /// in `text`, in any order. An empty query matches nothing.
    static func containsAllTokens(of query: String, in text: String) -> Bool {
        let tokens = normalized(query).split { $0.isWhitespace }
        let haystack = normalized(text)
        return !tokens.isEmpty && tokens.allSatisfy { haystack.contains($0) }
    }
}
