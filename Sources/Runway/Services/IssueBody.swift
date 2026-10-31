import Foundation

/// An issue's body, read as the sections a ticket is written in.
///
/// Runway asks for three of them by name: what done looks like, the ordered
/// steps to get there, and the conversation the issue lives in. A body
/// without them is not wrong, it simply has none to show.
enum IssueBody {
    struct Step: Identifiable, Equatable {
        /// The whole line as the issue holds it, blocker and all.
        let text: String
        let done: Bool
        var id: String { text }

        /// What this step is waiting on, written in the line itself as a
        /// trailing `(needs: ...)`. A step carries its own blocker, so there
        /// is no separate list to keep in step with the checklist.
        var needs: String? {
            guard let open = text.range(of: "(needs:", options: [.caseInsensitive, .backwards]),
                  text.hasSuffix(")") else { return nil }
            let inner = text[open.upperBound..<text.index(before: text.endIndex)]
            let said = inner.trimmingCharacters(in: .whitespaces)
            return said.isEmpty ? nil : said
        }

        /// The step without its blocker, which is what a card shows.
        var label: String {
            guard needs != nil,
                  let open = text.range(of: "(needs:", options: [.caseInsensitive, .backwards])
            else { return text }
            return text[text.startIndex..<open.lowerBound]
                .trimmingCharacters(in: .whitespaces)
        }
    }

    struct Entry: Identifiable, Equatable {
        let who: String
        let said: String
        let link: URL?
        var id: String { who + said }
    }

    /// The lines under one `## Heading`, up to the next heading of any depth.
    static func section(_ name: String, in body: String) -> [String] {
        var lines: [String] = []
        var inside = false
        for line in body.split(separator: "\n", omittingEmptySubsequences: false) {
            let text = String(line)
            let trimmed = text.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("#") {
                let heading = trimmed.drop { $0 == "#" }.trimmingCharacters(in: .whitespaces)
                // A heading can carry more than its name, as "Progress" does
                // when it also holds a date stamp.
                inside = heading.lowercased().hasPrefix(name.lowercased())
                continue
            }
            if inside { lines.append(text) }
        }
        return lines
    }

    /// Checklist lines, ticked or not, with the plain ones kept as unticked.
    static func steps(_ name: String, in body: String) -> [Step] {
        section(name, in: body).compactMap { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { return nil }
            if trimmed.hasPrefix("- [x]") || trimmed.hasPrefix("- [X]") {
                return Step(text: clean(String(trimmed.dropFirst(5))), done: true)
            }
            if trimmed.hasPrefix("- [ ]") {
                return Step(text: clean(String(trimmed.dropFirst(5))), done: false)
            }
            if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
                return Step(text: clean(String(trimmed.dropFirst(2))), done: false)
            }
            return nil
        }
    }

    /// The conversation log: `- [who](link): what happened.` under its
    /// heading, with day headers and anything else left out.
    static func conversation(_ name: String, in body: String) -> [Entry] {
        section(name, in: body).compactMap { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("- "), trimmed.contains("]("), trimmed.contains("): ") else {
                return nil
            }
            let rest = trimmed.dropFirst(2)
            guard let nameStart = rest.firstIndex(of: "["),
                  let nameEnd = rest.firstIndex(of: "]"),
                  nameStart < nameEnd else { return nil }
            let who = String(rest[rest.index(after: nameStart)..<nameEnd])
            let afterName = rest[rest.index(after: nameEnd)...]
            guard afterName.hasPrefix("("), let linkEnd = afterName.firstIndex(of: ")") else {
                return nil
            }
            let link = String(afterName[afterName.index(after: afterName.startIndex)..<linkEnd])
            var said = String(afterName[afterName.index(after: linkEnd)...])
            if said.hasPrefix(":") { said.removeFirst() }
            return Entry(
                who: who,
                said: clean(said),
                link: URL(string: link)
            )
        }
    }

    /// The first link in a conversation, which is where that conversation
    /// lives: the thread the issue was raised in.
    static func homeThread(_ name: String, in body: String) -> URL? {
        conversation(name, in: body).first?.link
    }

    private static func clean(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespaces)
    }
}
