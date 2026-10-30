import Foundation

/// A branch names its issue last: `feat/designer-images-page-16283` works on
/// issue 16283. Pulls reads it to offer that issue, and a long branch keeps
/// the number when the middle is truncated.
enum BranchIssue {
    /// The trailing `-<number>`, kept whole when the name is shortened.
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
