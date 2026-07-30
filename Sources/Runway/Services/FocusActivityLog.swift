import Foundation

struct FocusActivityEvent: Codable, Sendable {
    enum Action: String, Codable, Sendable {
        case enteredFocus = "entered_focus"
        case exitedFocus = "exited_focus"
    }

    let schemaVersion: Int
    let id: UUID
    let timestamp: Date
    let timeZone: String
    let action: Action
    let repository: String
    let issueNumber: Int
    let issueTitle: String
    let issueState: String
    let fromLane: AssignedIssueLane
    let toLane: AssignedIssueLane
    let cause: String
}

enum FocusActivityLog {
    private static let seededRepositoriesKey = "runway.focusActivitySeededRepositories.v1"

    static var file: URL {
        AgentControl.supportDir.appendingPathComponent("focus-activity.jsonl")
    }

    static func ensureFile() {
        let fileManager = FileManager.default
        try? fileManager.createDirectory(
            at: AgentControl.supportDir,
            withIntermediateDirectories: true
        )
        if !fileManager.fileExists(atPath: file.path) {
            fileManager.createFile(atPath: file.path, contents: nil)
        }
    }

    static func record(
        action: FocusActivityEvent.Action,
        repository: String,
        issue: AssignedIssue,
        from source: AssignedIssueLane,
        to destination: AssignedIssueLane,
        cause: String = "user"
    ) {
        ensureFile()
        let event = FocusActivityEvent(
            schemaVersion: 1,
            id: UUID(),
            timestamp: Date(),
            timeZone: TimeZone.current.identifier,
            action: action,
            repository: repository,
            issueNumber: issue.number,
            issueTitle: issue.title,
            issueState: issue.state,
            fromLane: source,
            toLane: destination,
            cause: cause
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard var data = try? encoder.encode(event) else { return }
        data.append(0x0A)
        guard let handle = try? FileHandle(forWritingTo: file) else { return }
        defer { try? handle.close() }
        do {
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
        } catch {
            return
        }
    }

    static func seedCurrentFocus(repository: String, issues: [AssignedIssue]) {
        var seeded = Set(
            UserDefaults.standard.stringArray(forKey: seededRepositoriesKey) ?? []
        )
        guard !seeded.contains(repository) else { return }
        for issue in issues {
            record(
                action: .enteredFocus,
                repository: repository,
                issue: issue,
                from: issue.isClosed ? .closed : .open,
                to: .focus,
                cause: "initial_snapshot"
            )
        }
        seeded.insert(repository)
        UserDefaults.standard.set(Array(seeded).sorted(), forKey: seededRepositoriesKey)
    }
}
