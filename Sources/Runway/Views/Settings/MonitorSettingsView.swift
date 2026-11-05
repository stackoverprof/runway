import SwiftUI

/// The "Monitor" Settings tab: what the Mac has, what Runway takes of it, and
/// where inside Runway it goes, live.
///
/// Read top to bottom it answers, in order: how busy is the Mac, how much of
/// that is Runway, how much of Runway is Claude, which flight is it, and
/// inside a flight which seat and which process. CPU is a share of the
/// whole Mac everywhere, so the figures add up against each other.
struct MonitorSettings: View {
    @State private var monitor = ResourceMonitor.shared
    /// The flight waiting on a yes before it is stopped.
    @State private var stopping: Int?
    /// The leftover waiting on a yes before it is quit.
    @State private var quitting: ResourceMonitor.Leftover?

    private var snapshot: ResourceMonitor.Snapshot { monitor.snapshot }

    /// One flight's seats, in the order they are read: pilot, copilot, crews.
    private struct FlightGroup: Identifiable {
        let id: Int
        var seats: [ResourceMonitor.Seat]
        var usage: ResourceMonitor.Usage { seats.reduce(.init()) { $0 + $1.usage } }
        var pilotUp: Bool { seats.contains { $0.rank == .pilot && $0.claude } }
        var crewsUp: Int { seats.filter { $0.rank == .crew && $0.claude }.count }
    }

    private var flights: [FlightGroup] {
        let grouped = Dictionary(grouping: snapshot.seats.filter { $0.flight != nil }) { $0.flight ?? 0 }
        return grouped.map { number, seats in
            FlightGroup(id: number, seats: seats.sorted { order($0) < order($1) })
        }
        .sorted { $0.usage.memory > $1.usage.memory }
    }

    private var looseSeats: [ResourceMonitor.Seat] {
        snapshot.seats.filter { $0.flight == nil }
    }

    private func order(_ seat: ResourceMonitor.Seat) -> (Int, Int) {
        switch seat.rank {
        case .pilot: (0, 0)
        case .copilot: (1, 0)
        case .crew: (2, seat.crew ?? 0)
        default: (3, 0)
        }
    }

    var body: some View {
        Form {
            Section("This Mac") {
                meter(
                    "Memory",
                    value: "\(memory(snapshot.macUsed)) of \(memory(snapshot.macTotal))",
                    fraction: Double(snapshot.macUsed) / Double(max(1, snapshot.macTotal))
                )
                meter("CPU", value: cpu(snapshot.macCPU), fraction: snapshot.macCPU / 100)
            }

            Section {
                line("Whole Runway", snapshot.total, strong: true)
                line(
                    "Claude sessions",
                    snapshot.usage(of: .claude),
                    note: "\(snapshot.claudeCount) running, Claude itself"
                )
                line(
                    "MCP servers",
                    snapshot.usage(of: .mcp),
                    note: "tools each Claude starts, one copy per session"
                )
                line("The app", snapshot.app, note: "windows, terminals")
                line("Background", snapshot.usage(of: .background), note: "servers, tests, builds")
                line("Shells", snapshot.usage(of: .shell))
            } header: {
                Text("Runway")
            } footer: {
                Text("CPU is a share of the whole Mac. Memory is each process's footprint, as Activity Monitor shows it. Updates every 2 seconds while this tab is open.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                if flights.isEmpty {
                    Text("No flight has a terminal open.")
                        .foregroundStyle(.secondary)
                }
                ForEach(flights) { group in
                    DisclosureGroup {
                        ForEach(group.seats) { seat in
                            seatBlock(seat, label: label(for: seat))
                        }
                    } label: {
                        flightLabel(group)
                    }
                }
            } header: {
                let pilots = flights.filter(\.pilotUp).count
                let crews = flights.reduce(0) { $0 + $1.crewsUp }
                Text("Flights · \(pilots) pilot\(pilots == 1 ? "" : "s"), \(crews) crew\(crews == 1 ? "" : "s") running")
            }

            if !snapshot.leftovers.isEmpty {
                Section {
                    ForEach(snapshot.leftovers) { leftover in
                        leftoverRow(leftover)
                    }
                } header: {
                    let total = snapshot.leftovers.reduce(UInt64(0)) { $0 + $1.usage.memory }
                    Text("Left behind · \(memory(total))")
                } footer: {
                    Text("Started from a Runway terminal, then detached: they keep running after their terminal closes, so neither Stop nor a relaunch reaches them. Stopping a flight closes its own leftovers, but never the shared ones (emulators, simulators, adb), since other flights may be using them.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if !looseSeats.isEmpty {
                Section("ATC") {
                    ForEach(looseSeats) { seat in
                        DisclosureGroup {
                            processRows(seat)
                        } label: {
                            figuresRow(seat.rank == .atc ? "ATC panel" : seat.name, seat.usage, strong: true)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .monospacedDigit()
        .onAppear { monitor.start() }
        .onDisappear { monitor.stop() }
        .confirmationDialog(
            "Stop \(stopping.map { title(of: $0) } ?? "this flight")?",
            isPresented: Binding(get: { stopping != nil }, set: { if !$0 { stopping = nil } }),
            titleVisibility: .visible
        ) {
            Button("Stop flight", role: .destructive) {
                if let number = stopping { stop(number) }
                stopping = nil
            }
            Button("Cancel", role: .cancel) { stopping = nil }
        } message: {
            Text("Its pilot, copilot and crews stop now, even mid-turn, along with anything they left running (servers, loops), except shared ones like the emulator. Their conversations are kept: opening the flight brings the pilot back where it left off.")
        }
        .confirmationDialog(
            "Quit \(quitting?.label ?? "it")?",
            isPresented: Binding(get: { quitting != nil }, set: { if !$0 { quitting = nil } }),
            titleVisibility: .visible
        ) {
            Button("Quit", role: .destructive) {
                if let leftover = quitting { ResourceMonitor.quit(leftover.pids) }
                quitting = nil
            }
            Button("Cancel", role: .cancel) { quitting = nil }
        } message: {
            Text(quitting?.shared == true
                 ? "Other flights may be using it. Anything they are running on it stops too."
                 : "It and everything it started close now.")
        }
    }

    // MARK: Rows

    private func leftoverRow(_ leftover: ResourceMonitor.Leftover) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(leftover.label).fontWeight(.semibold)
                Text(leftoverNote(leftover))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            figures(leftover.usage, strong: true)
            Button("Quit") { quitting = leftover }
                .controlSize(.small)
                .help("Close it and everything it started")
        }
    }

    private func leftoverNote(_ leftover: ResourceMonitor.Leftover) -> String {
        var parts = ["started by " + (leftover.flight.map { title(of: $0) } ?? leftover.startedBy)]
        if leftover.shared { parts.append("shared") }
        if leftover.pids.count > 1 { parts.append("\(leftover.pids.count) processes") }
        return parts.joined(separator: " · ")
    }

    private func meter(_ title: String, value: String, fraction: Double) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                Spacer()
                Text(value).fontWeight(.semibold)
            }
            ProgressView(value: min(max(fraction, 0), 1))
                .tint(fraction > 0.85 ? .red : (fraction > 0.65 ? .orange : .accentColor))
        }
    }

    /// A row in the Runway section: name, an optional grey note, figures.
    private func line(_ title: String, _ usage: ResourceMonitor.Usage, note: String? = nil, strong: Bool = false) -> some View {
        HStack(spacing: 8) {
            Text(title).fontWeight(strong ? .semibold : .regular)
            if let note {
                Text(note).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            figures(usage, strong: strong)
        }
        .padding(.leading, strong ? 0 : 12)
    }

    private func flightLabel(_ group: FlightGroup) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title(of: group.id)).fontWeight(.semibold)
                Text(summary(group))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            figures(group.usage, strong: true)
            stopButton(group)
        }
    }

    private func summary(_ group: FlightGroup) -> String {
        var parts = [group.pilotUp ? "pilot running" : "pilot stopped"]
        parts.append("\(group.crewsUp) crew\(group.crewsUp == 1 ? "" : "s")")
        if group.seats.contains(where: { $0.rank == .copilot && $0.claude }) { parts.append("copilot") }
        let mcp = group.seats.reduce(0) { $0 + $1.processes.filter { $0.kind == .mcp }.count }
        if mcp > 0 { parts.append("\(mcp) MCP") }
        let background = group.seats.reduce(0) { $0 + $1.processes.filter { $0.kind == .background }.count }
        if background > 0 { parts.append("\(background) background") }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private func seatBlock(_ seat: ResourceMonitor.Seat, label: String) -> some View {
        figuresRow(label + (seat.claude ? "" : "  (no Claude)"), seat.usage, strong: false)
        processRows(seat)
            .padding(.leading, 16)
    }

    @ViewBuilder
    private func processRows(_ seat: ResourceMonitor.Seat) -> some View {
        ForEach(seat.processes) { process in
            HStack {
                Text(process.label)
                    .font(.callout)
                    .foregroundStyle(process.kind == .claude ? .primary : .secondary)
                Spacer()
                figures(process.usage, strong: false)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func figuresRow(_ title: String, _ usage: ResourceMonitor.Usage, strong: Bool) -> some View {
        HStack {
            Text(title).fontWeight(strong ? .semibold : .regular)
            Spacer()
            figures(usage, strong: strong)
        }
    }

    /// Memory and CPU in two fixed columns, so every row lines up.
    private func figures(_ usage: ResourceMonitor.Usage, strong: Bool) -> some View {
        HStack(spacing: 10) {
            Text(memory(usage.memory))
                .fontWeight(strong ? .semibold : .regular)
                .lineLimit(1)
                .frame(width: 78, alignment: .trailing)
            Text(cpu(usage.cpu))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(width: 64, alignment: .trailing)
        }
    }

    // MARK: Stopping a flight

    /// The main window's context: which flight is on screen, and the board.
    /// Settings is the key window while this tab is open, so the active
    /// context alone comes back empty.
    private var context: RunwayWindowContext? {
        RunwayWindowRegistry.shared.activeContext() ?? RunwayWindowRegistry.shared.allContexts.first
    }

    private func stopButton(_ group: FlightGroup) -> some View {
        let onScreen = context?.workspace.flightNumber == group.id
        return Button("Stop") { stopping = group.id }
            .controlSize(.small)
            .disabled(onScreen || context?.issues.issue(group.id) == nil)
            .help(onScreen ? "This flight is on screen. Open another one to stop it." : "Stop every session of this flight")
    }

    private func stop(_ number: Int) {
        guard let context, let board = context.issues.repository,
              let flight = context.issues.issue(number) else { return }
        FlightDozer.shared.stopNow(flight, board: board)
    }

    // MARK: Words and numbers

    private func label(for seat: ResourceMonitor.Seat) -> String {
        switch seat.rank {
        case .pilot: return "Pilot"
        case .copilot: return "Copilot"
        case .crew:
            let number = seat.crew.map { GitHubNumber.reference($0) } ?? ""
            let name = seat.crew.flatMap { issueTitle($0) } ?? seat.name
            return "Crew \(number) \(name)"
        default: return seat.name
        }
    }

    private func title(of flight: Int) -> String {
        "\(issueTitle(flight) ?? "Flight") \(GitHubNumber.reference(flight))"
    }

    private func issueTitle(_ number: Int) -> String? {
        let issues = context?.issues
        if let title = issues?.issue(number)?.title { return title }
        return issues?.issues.lazy.compactMap { $0.legs.first { $0.number == number }?.title }.first
    }

    private func memory(_ bytes: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .memory)
    }

    private func cpu(_ percent: Double) -> String {
        percent < 0.5 && percent > 0 ? "<1% CPU" : "\(Int(percent.rounded()))% CPU"
    }
}
