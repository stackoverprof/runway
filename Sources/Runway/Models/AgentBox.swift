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

    enum CodingKeys: String, CodingKey { case id, name, detail, height, cwd }
}
