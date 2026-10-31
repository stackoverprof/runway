import Foundation

/// The order crews fly in, taken from the pilot's checklist.
///
/// The sub-issue order is whatever order they were adopted in, which is
/// nobody's intent. The Progress list is the pilot's actual sequence, so a
/// crew sits where its step sits: a step naming `#16791`, or whose words are
/// the crew's own title, puts that crew at that point in the run. A crew no
/// step mentions keeps its place after the ones that are named.
enum CrewOrder {
    /// Crews, live ones first in checklist order, landed ones after.
    static func sorted(_ crews: [IssueLeg], by steps: [IssueBody.Step]) -> [IssueLeg] {
        let places = places(for: crews, in: steps)
        let ranked = crews.enumerated().sorted { left, right in
            let a = places[left.element.number] ?? Int.max
            let b = places[right.element.number] ?? Int.max
            if a != b { return a < b }
            return left.offset < right.offset
        }.map(\.element)
        return ranked.filter { !$0.isClosed } + ranked.filter(\.isClosed)
    }

    /// Which step each crew belongs to, by the number it names or the words
    /// it uses.
    static func places(for crews: [IssueLeg], in steps: [IssueBody.Step]) -> [Int: Int] {
        var places: [Int: Int] = [:]
        for (index, step) in steps.enumerated() {
            let label = tidy(step.label)
            for crew in crews where places[crew.number] == nil {
                if step.label.contains("#\(crew.number)") {
                    places[crew.number] = index
                    continue
                }
                let title = tidy(subject(of: crew.title))
                guard title.count >= 4 else { continue }
                if label.contains(title) || title.contains(label), !label.isEmpty {
                    places[crew.number] = index
                }
            }
        }
        return places
    }

    /// `Dependency: Sentry 11 upgrade` is about `Sentry 11 upgrade`. The
    /// cluster prefix is the flight's name, not the crew's subject, and it
    /// matches every step equally well.
    private static func subject(of title: String) -> String {
        guard let colon = title.firstIndex(of: ":") else { return title }
        return String(title[title.index(after: colon)...])
    }

    private static func tidy(_ text: String) -> String {
        text.lowercased()
            .map { $0.isLetter || $0.isNumber ? $0 : " " }
            .reduce(into: "") { tidied, character in
                if character == " ", tidied.last == " " { return }
                tidied.append(character)
            }
            .trimmingCharacters(in: .whitespaces)
    }
}
