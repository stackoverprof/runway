import SwiftUI

/// Lifecycle state of an agent, shown as the colored header dot.
enum AgentState: String {
    case idle
    case running
    case needsAction

    /// Lenient parse of the `state` value written to the control file.
    init(control value: String) {
        switch value.lowercased().replacingOccurrences(of: "_", with: "-") {
        case "running", "busy", "working": self = .running
        case "needs-action", "needsaction", "attention", "waiting", "blocked", "input": self = .needsAction
        default: self = .idle
        }
    }

    var color: Color {
        switch self {
        case .idle: return Color(red: 0.42, green: 0.45, blue: 0.50)        // grey
        case .running: return Color(red: 0.247, green: 0.725, blue: 0.314)  // green
        case .needsAction: return Color(red: 0.91, green: 0.62, blue: 0.20) // amber
        }
    }

    var glows: Bool { self != .idle }
}
