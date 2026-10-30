import Foundation

/// Who an agent is in Runway.
///
/// The tower sits above every flight and belongs to none. A pilot flies one
/// flight, which is one issue, with a copilot beside it when the work needs
/// two. A crew answers for one of that flight's sub-issues.
enum AgentRank: String, Codable, CaseIterable {
    case atc
    case pilot
    case copilot
    case crew

    var label: String {
        switch self {
        case .atc: "Air Traffic Controller"
        case .pilot: "Pilot"
        case .copilot: "Copilot"
        case .crew: "Crew"
        }
    }
}
