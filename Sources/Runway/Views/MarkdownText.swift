import SwiftUI

/// Issue text as GitHub writes it, read the way GitHub reads it.
///
/// An issue body is Markdown, so a line like `[#17340](https://…) reviewed`
/// is a link, not that whole string of characters. Rendering it raw put the
/// URL on screen twice and pushed the sentence onto three lines.
struct MarkdownText: View {
    let text: String
    var tint: Color = Runway.teal

    var body: some View {
        Text(Self.attributed(text))
            .tint(tint)
    }

    /// Markdown with the line breaks left alone. A line that will not parse
    /// comes back as itself, so nothing is ever lost to a stray bracket.
    static func attributed(_ text: String) -> AttributedString {
        (try? AttributedString(
            markdown: text,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(text)
    }
}
