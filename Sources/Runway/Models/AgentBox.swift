import Foundation

/// One agent box: an editable name + its own height. Stable `id` so each box's
/// terminal session survives renames, resizes, and adding new boxes.
struct AgentBox: Identifiable, Codable {
    var id = UUID()
    var name: String
    var detail: String = ""
    var state: AgentState = .idle   // runtime only, not persisted
    var height: CGFloat = 264
    var cwd: String?                // last working directory, restored on relaunch
    var autorun: String?            // one-time command for new boxes, not persisted
    var focusRepository: String?    // Focus-owned terminal identity
    var focusIssueNumber: Int?
    /// The clone whose Focus board owns this box, when it is not the
    /// repository's preferred clone. Nil for the preferred one.
    var focusCheckout: String?

    enum CodingKeys: String, CodingKey {
        case id, name, detail, height, cwd, focusRepository, focusIssueNumber, focusCheckout
    }

    var focusBoard: String? {
        focusRepository.map { FocusBoard.key($0, checkout: focusCheckout) }
    }
}

/// Each clone of a repository keeps its own Focus board. The preferred clone's
/// board is keyed by the bare repository, so boards saved before clones had
/// boards of their own stay where they were.
enum FocusBoard {
    static func key(_ repository: String, checkout: String?) -> String {
        checkout.map { "\(repository)@\($0)" } ?? repository
    }
}
