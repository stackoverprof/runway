import Foundation

/// A branch names its issue last: `feat/designer-images-page-16283` works on
/// issue 16283. Runway reads it to tell which flight or crew a pull request
/// belongs to, and keeps the number when a long branch is truncated.
enum BranchIssue {
    static func split(_ name: String) -> (stem: String, number: String?) {
        guard let dash = name.lastIndex(of: "-"), dash != name.startIndex else { return (name, nil) }
        let suffix = name[name.index(after: dash)...]
        guard !suffix.isEmpty, suffix.allSatisfy(\.isNumber) else { return (name, nil) }
        return (String(name[..<dash]), String(name[dash...]))
    }

    static func number(in name: String) -> Int? {
        split(name).number.map { $0.dropFirst() }.flatMap { Int($0) }
    }
}
