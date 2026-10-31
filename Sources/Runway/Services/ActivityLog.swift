import Foundation

/// What happened in Runway, one line at a time.
///
/// The reports Erbin writes at the end of a day or a week need to know where
/// his attention went and what actually moved. v2 could only say which issue
/// was in the Focus lane and when; v3 sees the work itself pass through it, so
/// it records that too: a step ticked, a blocker set, a crew that ran, an
/// issue closed. GitHub stays the evidence. This is the thread to follow.
@MainActor
enum ActivityLog {
    static var file: URL {
        RunwayStorage.supportDir.appendingPathComponent("activity.jsonl")
    }

    /// Append one event. Never throws and never blocks on anything: a report
    /// that loses a line is a smaller problem than a pane that stutters.
    static func write(_ action: String, _ fields: [String: Any] = [:]) {
        var line: [String: Any] = fields
        line["action"] = action
        line["at"] = ISO8601DateFormatter().string(from: Date())
        line["schema"] = 2
        guard let data = try? JSONSerialization.data(withJSONObject: line, options: [.sortedKeys]),
              var text = String(data: data, encoding: .utf8) else { return }
        text += "\n"
        append(text)
    }

    private static func append(_ text: String) {
        let url = file
        try? FileManager.default.createDirectory(
            at: RunwayStorage.supportDir,
            withIntermediateDirectories: true
        )
        guard let data = text.data(using: .utf8) else { return }
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: url)
        }
    }

    // MARK: What the app records

    /// The flight you turned your attention to, and the one you left.
    static func flightOpened(_ number: Int, title: String, repository: String) {
        write("flight_opened", ["issue": number, "title": title, "repository": repository])
    }

    static func flightLeft(_ number: Int, title: String, repository: String, seconds: Int) {
        write("flight_left", [
            "issue": number,
            "title": title,
            "repository": repository,
            "seconds": seconds,
        ])
    }

    /// A crew's terminal opened or stood down, whoever did it.
    static func crewUp(_ number: Int, title: String, repository: String) {
        write("crew_up", ["issue": number, "title": title, "repository": repository])
    }

    static func crewDown(_ number: Int, title: String, repository: String, seconds: Int) {
        write("crew_down", [
            "issue": number,
            "title": title,
            "repository": repository,
            "seconds": seconds,
        ])
    }

    /// How long a seat's agent actually worked, measured from the control
    /// file that already drives the dot.
    static func seatWorked(
        rank: AgentRank,
        issue: Int,
        repository: String,
        name: String,
        seconds: Int
    ) {
        guard seconds >= 20 else { return }
        write("seat_worked", [
            "rank": rank.rawValue,
            "issue": issue,
            "repository": repository,
            "name": name,
            "seconds": seconds,
        ])
    }
}
