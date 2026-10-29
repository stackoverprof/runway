import SwiftUI
import AppKit

/// A user-defined shortcut that runs a shell command in the background, such
/// as a script that refreshes a board and reorders the Open lane, or a
/// headless `claude -p` task. A banner says it started and how it ended.
struct CustomCommand: Codable, Equatable, Identifiable {
    var id = UUID()
    var text = ""
    var chord: KeyChord?
}

@MainActor @Observable final class CustomCommands {
    static let shared = CustomCommands()
    private(set) var commands: [CustomCommand] = []
    @ObservationIgnored private var running: Set<UUID> = []
    private static let key = "runway.customCommands"

    private init() { load() }

    func add() {
        commands.append(CustomCommand())
        save()
    }

    func update(_ command: CustomCommand) {
        guard let index = commands.firstIndex(where: { $0.id == command.id }) else { return }
        commands[index] = command
        save()
    }

    func remove(_ id: UUID) {
        commands.removeAll { $0.id == id }
        save()
    }

    /// The command a key event triggers, if any has text and a matching chord.
    func command(for event: NSEvent) -> CustomCommand? {
        commands.first {
            !$0.text.trimmingCharacters(in: .whitespaces).isEmpty && $0.chord?.matches(event) == true
        }
    }

    /// Runs the command in a login shell in the checkout on screen, with the
    /// same Runway helpers on PATH as an agent terminal, so `runway-issue`
    /// acts on the board in front of you. Pressing the shortcut again while it
    /// runs does nothing.
    func run(_ command: CustomCommand, in ws: Workspace) {
        guard !running.contains(command.id) else { return }
        let repository = ws.repositoryFeed?.repo ?? GitHubFeed.shared.repo
        let directory = GitHubFeed.shared.localPath(for: repository)
            ?? FileManager.default.homeDirectoryForCurrentUser.path
        let log = FileManager.default.temporaryDirectory
            .appendingPathComponent("runway-command-\(command.id.uuidString).log")
        FileManager.default.createFile(atPath: log.path, contents: nil)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", command.text]
        process.currentDirectoryURL = URL(fileURLWithPath: directory)
        var environment = ProcessInfo.processInfo.environment
        environment.merge(
            AgentControl.environment(for: UUID(), focusRepository: repository)
        ) { _, runway in runway }
        environment.removeValue(forKey: "ZDOTDIR")   // the user's own shell setup
        process.environment = environment
        process.standardInput = FileHandle.nullDevice
        if let handle = try? FileHandle(forWritingTo: log) {
            process.standardOutput = handle
            process.standardError = handle
        }

        let title = command.text.trimmingCharacters(in: .whitespacesAndNewlines)
        process.terminationHandler = { [weak ws] finished in
            let status = finished.terminationStatus
            Task { @MainActor in
                CustomCommands.shared.running.remove(command.id)
                guard let ws else { return }
                ws.finishCommandBanner(command.id, exitCode: status, log: log)
                // Whatever the command changed on GitHub or the board shows now.
                ws.requestSourceRefresh(.runway)
            }
        }
        do {
            try process.run()
            running.insert(command.id)
            ws.showCommandBanner(id: command.id, title: title)
        } catch {
            ws.showCommandBanner(id: command.id, title: title)
            ws.finishCommandBanner(command.id, exitCode: -1, log: log)
        }
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: Self.key),
              let saved = try? JSONDecoder().decode([CustomCommand].self, from: data) else { return }
        commands = saved
    }

    private func save() {
        if let data = try? JSONEncoder().encode(commands) { UserDefaults.standard.set(data, forKey: Self.key) }
    }
}

/// One custom command in Settings, laid out like the built-in shortcut rows:
/// the command on the left, its shortcut on the right.
struct CustomCommandRow: View {
    let command: CustomCommand
    @Bindable private var store = CustomCommands.shared
    @State private var text = ""

    var body: some View {
        HStack {
            TextField("Command", text: $text, prompt: Text("Shell command"))
                .labelsHidden()
                .textFieldStyle(.plain)
                .font(.system(.body, design: .monospaced))
                .onChange(of: text) { _, _ in commit() }
            ChordRecorderButton(display: command.chord?.display ?? "Set shortcut") { chord in
                var next = command
                next.chord = chord
                store.update(next)
            }
            Button { store.remove(command.id) } label: { Image(systemName: "trash") }
                .buttonStyle(.borderless)
                .help("Remove command")
                .pointerCursor()
        }
        .onAppear { text = command.text }
    }

    private func commit() {
        guard text != command.text else { return }
        var next = command
        next.text = text
        store.update(next)
    }
}
