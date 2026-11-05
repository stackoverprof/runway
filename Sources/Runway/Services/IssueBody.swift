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

        /// The checklist's own last line, the one that says "and then it is
        /// closed". It is not work, so nothing counts it as progress.
        ///
        /// It used to read `/close`, after the skill of that name. The skill
        /// is retired and Runway does the closing, so new checklists say
        /// `land it`; issues filed before the change still say the old thing.
        var isLanding: Bool {
            let said = label
                .trimmingCharacters(in: .whitespaces)
                .lowercased()
            return said == "/close" || said == "land it" || said == "close it"
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
        /// The day header this entry sits under, as the log writes it:
        /// `Fri, 30 Oct`. Nil when the log has no headers.
        var day: String?
        var id: String { (day ?? "") + who + said }
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
        var day: String?
        return section(name, in: body).compactMap { line -> Entry? in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            // A bold line of its own is the day the entries under it happened.
            if trimmed.hasPrefix("**"), trimmed.hasSuffix("**"), !trimmed.hasPrefix("- ") {
                let header = trimmed.dropFirst(2).dropLast(2)
                    .trimmingCharacters(in: .whitespaces)
                if !header.lowercased().hasPrefix("channel") { day = header }
                return nil
            }
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
                link: URL(string: link),
                day: day
            )
        }
    }

    /// A checklist in the order it really happened: what is done first, in
    /// the order written, then what is still to do, and the landing line
    /// last. Work rarely goes in the order first planned, and a board that
    /// read LANDED, BOARDING, LANDED, SCHEDULED, LANDED told no story. The
    /// `runway` CLI numbers and saves steps in this same order, so a number
    /// on the board is the number an agent ticks.
    static func inFlightOrder(_ steps: [Step]) -> [Step] {
        steps.filter { $0.done && !$0.isLanding }
            + steps.filter { !$0.done && !$0.isLanding }
            + steps.filter(\.isLanding)
    }

    /// The log newest first, however it was written. Agents kept adding new
    /// lines under the old ones, which buried the latest exchange at the
    /// bottom of the pane. Each line's Slack permalink carries the moment it
    /// was sent (`p1790226902634849`), so that is the order; a line without
    /// one takes its day header's date and stays beside its neighbours.
    static func newestFirst(_ entries: [Entry], now: Date = Date()) -> [Entry] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let year = calendar.component(.year, from: now)
        let parser = DateFormatter()
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.dateFormat = "d MMM yyyy"
        func dayDate(_ day: String?) -> Date? {
            guard let day else { return nil }
            let bare = day.split(separator: ",").last.map(String.init)?
                .trimmingCharacters(in: .whitespaces) ?? day
            guard let date = parser.date(from: "\(bare) \(year)") else { return nil }
            // "28 Dec" read in January is last year's.
            if date > now.addingTimeInterval(86_400),
               let earlier = calendar.date(byAdding: .year, value: -1, to: date) { return earlier }
            return date
        }
        func stamp(_ link: URL?) -> Date? {
            guard let last = link?.pathComponents.last, last.hasPrefix("p"),
                  let digits = Double(last.dropFirst()), digits > 1e15 else { return nil }
            return Date(timeIntervalSince1970: digits / 1_000_000)
        }
        let keyed = entries.enumerated().map { index, entry -> (Entry, Date, Int) in
            let when = stamp(entry.link)
                ?? dayDate(entry.day).map { $0.addingTimeInterval(43_200) }
                ?? .distantPast
            return (entry, when, index)
        }
        return keyed
            .sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.2 < $1.2 }
            .map(\.0)
    }

    /// The first link in a conversation, which is where that conversation
    /// lives: the thread the issue was raised in.
    static func homeThread(_ name: String, in body: String) -> URL? {
        conversation(name, in: body).first?.link
    }

    /// One place the conversation lives: a name, and a link when it has one.
    struct Channel: Identifiable, Equatable {
        let name: String
        let link: URL?
        var id: String { name + (link?.absoluteString ?? "") }
    }

    /// Every channel the log names, in the order written. A flight gathered
    /// from several crews often has more than one, and a single button
    /// cannot say that without becoming a paragraph.
    static func channels(_ name: String, in body: String) -> [Channel] {
        guard let said = homeChannel(name, in: body) else { return [] }
        var found: [Channel] = []
        var rest = Substring(said)
        while let open = rest.firstIndex(of: "["),
              let close = rest[open...].firstIndex(of: "]"),
              rest.index(after: close) < rest.endIndex,
              rest[rest.index(after: close)] == "(",
              let end = rest[close...].firstIndex(of: ")") {
            let label = String(rest[rest.index(after: open)..<close])
            let url = String(rest[rest.index(close, offsetBy: 2)..<end])
            found.append(Channel(name: label, link: URL(string: url)))
            rest = rest[rest.index(after: end)...]
        }
        if found.isEmpty {
            for part in said.split(separator: ",") {
                let text = part.trimmingCharacters(in: .whitespaces)
                if !text.isEmpty { found.append(Channel(name: text, link: nil)) }
            }
        }
        return found
    }

    /// Where the conversation lives, as the log names it on its first line:
    /// `**Channel:** #upsell-dashboard`, or a DM.
    static func homeChannel(_ name: String, in body: String) -> String? {
        for line in section(name, in: body) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard let colon = trimmed.range(of: "Channel:", options: .caseInsensitive) else {
                continue
            }
            let said = trimmed[colon.upperBound...]
                .replacingOccurrences(of: "*", with: "")
                .trimmingCharacters(in: .whitespaces)
            return said.isEmpty ? nil : said
        }
        return nil
    }

    private static func clean(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespaces)
    }
}


extension Array {
    /// The element at `index`, or nil when there is none. Reading the entry
    /// before this one is the natural way to ask "is this a new day?".
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
