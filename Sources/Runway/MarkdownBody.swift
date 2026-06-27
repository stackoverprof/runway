import SwiftUI
import MarkdownUI

/// Agent-post markdown via [MarkdownUI](https://github.com/gonzalezreal/swift-markdown-ui) (GFM).
struct MarkdownBody: View {
    let source: String

    var body: some View {
        Markdown(normalized)
            .markdownTheme(Self.feedTheme)
            .font(.system(size: 11))
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    @MainActor private static let feedTheme = runwayFeedTheme()

    /// Shell posts often arrive with literal `\n`; normalize before parsing.
    private var normalized: String {
        source.replacingOccurrences(of: "\\n", with: "\n")
            .replacingOccurrences(of: "\\t", with: "\t")
            .replacingOccurrences(of: "\\r", with: "\r")
    }

    @MainActor
    private static func runwayFeedTheme() -> Theme {
        Theme()
        .text {
            FontSize(11)
            ForegroundColor(Color.white.opacity(0.62))
        }
        .strong {
            FontWeight(.semibold)
            ForegroundColor(Color.white.opacity(0.78))
        }
        .emphasis {
            FontStyle(.italic)
        }
        .code {
            FontFamilyVariant(.monospaced)
            FontSize(10)
            ForegroundColor(Color.white.opacity(0.78))
            BackgroundColor(Color.white.opacity(0.08))
        }
        .link {
            ForegroundColor(Color(red: 0.45, green: 0.82, blue: 0.78))
        }
        .heading1 { c in
            c.label
                .markdownMargin(top: .em(0.2), bottom: .em(0.08))
                .markdownTextStyle {
                    FontWeight(.semibold)
                    FontSize(11.5)
                    ForegroundColor(Color.white.opacity(0.9))
                }
        }
        .heading2 { c in
            c.label
                .markdownMargin(top: .em(0.25), bottom: .em(0.06))
                .markdownTextStyle {
                    FontWeight(.semibold)
                    FontSize(11)
                    ForegroundColor(Color.white.opacity(0.88))
                }
        }
        .heading3 { c in
            c.label
                .markdownMargin(top: .em(0.2), bottom: .em(0.05))
                .markdownTextStyle {
                    FontWeight(.semibold)
                    FontSize(11)
                    ForegroundColor(Color.white.opacity(0.85))
                }
        }
        .paragraph { c in
            c.label
                .fixedSize(horizontal: false, vertical: true)
                .relativeLineSpacing(.em(0.08))
                .markdownMargin(top: .zero, bottom: .em(0.3))
        }
        .listItem { c in
            c.label
                .markdownMargin(top: .em(0.04))
        }
        .blockquote { c in
            c.label
                .markdownTextStyle { ForegroundColor(Color.white.opacity(0.5)) }
                .relativePadding(.leading, length: .em(1))
                .overlay(alignment: .leading) {
                    Rectangle()
                        .fill(Color.white.opacity(0.15))
                        .frame(width: 2)
                }
        }
        .codeBlock { c in
            c.label
                .fixedSize(horizontal: false, vertical: true)
                .relativeLineSpacing(.em(0.08))
                .relativePadding(.horizontal, length: .em(0.55))
                .relativePadding(.vertical, length: .em(0.35))
                .markdownTextStyle {
                    FontFamilyVariant(.monospaced)
                    FontSize(10)
                    ForegroundColor(Color.white.opacity(0.78))
                }
                .background(Color.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .markdownMargin(top: .em(0.1), bottom: .em(0.25))
        }
    }
}
