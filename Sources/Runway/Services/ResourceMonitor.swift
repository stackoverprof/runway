import Darwin
import Foundation

/// What Runway costs the Mac right now: the app itself, and every process it
/// started, grouped by the seat (pilot, copilot, crew, ATC) that owns it.
///
/// Read straight from the kernel, the way Activity Monitor does: memory is
/// each process's physical footprint. CPU is a share of the whole Mac (all
/// cores together), so every figure on the tab adds up against the Mac's
/// own. A seat is found by the `RUNWAY_CONTROL` path every terminal Runway
/// opens carries in its environment, which every process in that terminal
/// inherits, so a shell, claude itself and anything claude runs (a dev
/// server, a test) all add up under the one seat.
@MainActor @Observable
final class ResourceMonitor {
    static let shared = ResourceMonitor()

    enum Rank: String {
        case pilot, copilot, crew, atc, other
    }

    /// What a process is, to the person reading the tab.
    enum Kind: String {
        case claude, mcp, shell, background
    }

    struct Usage: Equatable {
        var memory: UInt64 = 0
        var cpu: Double = 0

        static func + (a: Usage, b: Usage) -> Usage {
            Usage(memory: a.memory + b.memory, cpu: a.cpu + b.cpu)
        }
    }

    struct Process: Identifiable, Equatable {
        let id: Int32
        let kind: Kind
        let label: String
        let usage: Usage
    }

    /// Something a Runway seat started that outlived its terminal: it
    /// detached, its terminal closed, and it now belongs to macOS. Stopping a
    /// flight or relaunching Runway never reaches it.
    struct Leftover: Identifiable, Equatable {
        let id: Int32
        let label: String
        /// The seat that started it, as its session is named.
        let startedBy: String
        let flight: Int?
        /// Used by every flight (an emulator, a simulator, adb), so Stop
        /// leaves it running; only its own Quit closes it.
        let shared: Bool
        let pids: [Int32]
        let usage: Usage
    }

    struct Seat: Identifiable, Equatable {
        let id: String
        let name: String
        let rank: Rank
        let flight: Int?
        let crew: Int?
        let processes: [Process]
        var usage: Usage { processes.reduce(Usage()) { $0 + $1.usage } }
        /// Whether Claude is running in it, rather than a bare shell.
        var claude: Bool { processes.contains { $0.kind == .claude } }
        func usage(of kind: Kind) -> Usage {
            processes.filter { $0.kind == kind }.reduce(Usage()) { $0 + $1.usage }
        }
    }

    struct Snapshot: Equatable {
        var app = Usage()
        var seats: [Seat] = []
        var macUsed: UInt64 = 0
        var macTotal: UInt64 = ProcessInfo.processInfo.physicalMemory
        var macCPU: Double = 0
        var at = Date.distantPast

        var total: Usage { seats.reduce(app) { $0 + $1.usage } }
        func usage(of kind: Kind) -> Usage { seats.reduce(Usage()) { $0 + $1.usage(of: kind) } }
        var claudeCount: Int { seats.reduce(0) { $0 + $1.processes.filter { $0.kind == .claude }.count } }
        var leftovers: [Leftover] = []
    }

    private(set) var snapshot = Snapshot()
    private var previousCPU: [pid_t: UInt64] = [:]
    private var previousAt: UInt64 = 0
    private var previousTicks: [UInt32] = []
    private var watchers = 0
    private var loop: Task<Void, Never>?

    /// Sample every two seconds while anyone is looking.
    func start() {
        watchers += 1
        guard loop == nil else { return }
        loop = Task { [weak self] in
            while !Task.isCancelled {
                await self?.sample()
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }
    }

    func stop() {
        watchers = max(0, watchers - 1)
        guard watchers == 0 else { return }
        loop?.cancel()
        loop = nil
    }

    private func sample() async {
        let previous = previousCPU
        let previousAt = previousAt
        let ticks = previousTicks
        let result = await Task.detached(priority: .utility) {
            Self.read(previousCPU: previous, previousAt: previousAt, previousTicks: ticks)
        }.value
        previousCPU = result.cpu
        self.previousAt = result.at
        previousTicks = result.ticks
        snapshot = result.snapshot
    }

    // MARK: Reading the kernel

    private struct Proc {
        let pid: pid_t
        let ppid: pid_t
        let uid: uid_t
        let name: String
        let memory: UInt64
        let cpuNanos: UInt64
    }

    private struct Reading {
        let snapshot: Snapshot
        let cpu: [pid_t: UInt64]
        let at: UInt64
        let ticks: [UInt32]
    }

    nonisolated private static let cores = Double(max(1, ProcessInfo.processInfo.activeProcessorCount))

    nonisolated private static func read(
        previousCPU: [pid_t: UInt64],
        previousAt: UInt64,
        previousTicks: [UInt32]
    ) -> Reading {
        let now = DispatchTime.now().uptimeNanoseconds
        let me = getpid()
        let all = allProcesses()
        var children: [pid_t: [pid_t]] = [:]
        for proc in all.values { children[proc.ppid, default: []].append(proc.pid) }

        // Runway and everything under it.
        var tree: [pid_t] = []
        var queue = [me]
        while let pid = queue.popLast() {
            tree.append(pid)
            queue.append(contentsOf: children[pid] ?? [])
        }

        let wall = previousAt == 0 ? 0 : Double(now - previousAt)
        var cpuNow: [pid_t: UInt64] = [:]
        func usage(_ proc: Proc) -> Usage {
            cpuNow[proc.pid] = proc.cpuNanos
            var share = 0.0
            if wall > 0, let before = previousCPU[proc.pid], proc.cpuNanos >= before {
                share = Double(proc.cpuNanos - before) / wall * 100 / cores
            }
            return Usage(memory: proc.memory, cpu: share)
        }

        var app = Usage()
        var groups: [String: (env: [String: String], processes: [Process])] = [:]
        for pid in tree {
            guard let proc = all[pid] else { continue }
            let used = usage(proc)
            if pid == me {
                app = app + used
                continue
            }
            let launch = arguments(of: pid)
            guard let control = launch.env["RUNWAY_CONTROL"] else {
                app = app + used
                continue
            }
            let key = URL(fileURLWithPath: control).deletingPathExtension().lastPathComponent
            let (kind, label) = describe(proc, launch: launch)
            var group = groups[key] ?? (launch.env, [])
            group.processes.append(Process(id: pid, kind: kind, label: label, usage: used))
            groups[key] = group
        }

        var seats: [Seat] = groups.map { key, group in
            let env = group.env
            let flight = env["RUNWAY_FLIGHT"].flatMap { Int($0) }
            let crew = env["RUNWAY_CREW"].flatMap { Int($0) }
            let name = env["RUNWAY_SESSION_NAME"] ?? env["RUNWAY_AGENT_NAME"] ?? "terminal"
            let rank: Rank
            if let stated = env["RUNWAY_RANK"].flatMap(Rank.init(rawValue:)) {
                rank = stated
            } else if crew != nil {
                rank = .crew
            } else if flight != nil {
                rank = name.hasSuffix("-copilot") ? .copilot : .pilot
            } else {
                rank = .other
            }
            let processes = group.processes.sorted { $0.usage.memory > $1.usage.memory }
            return Seat(id: key, name: name, rank: rank, flight: flight, crew: crew, processes: processes)
        }
        seats.sort { $0.usage.memory > $1.usage.memory }

        let ticks = cpuTicks()
        var snapshot = Snapshot()
        snapshot.app = app
        snapshot.seats = seats
        snapshot.macUsed = macMemoryUsed()
        snapshot.macCPU = macCPU(ticks, since: previousTicks)
        snapshot.leftovers = leftovers(all: all, children: children, usage: usage)
        snapshot.at = Date()
        return Reading(snapshot: snapshot, cpu: cpuNow, at: now, ticks: ticks)
    }

    nonisolated private static let shells: Set<String> = ["zsh", "-zsh", "bash", "-bash", "sh", "fish", "login", "tmux"]

    /// Claude, a shell, or something running in the background (a dev
    /// server, a test run, a build), named the way you would say it.
    nonisolated private static func describe(
        _ proc: Proc,
        launch: (exec: String, argv: [String], env: [String: String])
    ) -> (Kind, String) {
        let argv0 = (launch.argv.first as NSString?)?.lastPathComponent ?? ""
        if shells.contains(proc.name) || shells.contains(argv0) {
            // The wrapper Runway puts in front of claude is a zsh script.
            return (.shell, proc.name.trimmingCharacters(in: CharacterSet(charactersIn: "-")))
        }
        let isClaude = argv0 == "claude"
            || launch.exec.contains("/claude/")
            || launch.argv.contains { $0.contains("claude-code") }
        if isClaude { return (.claude, "Claude") }
        // A tool server Claude starts for itself, one per session: Maestro
        // runs as `java ... maestro.cli.AppKt mcp`, and is 200 MB a copy.
        if launch.argv.contains(where: { $0.lowercased() == "mcp" || $0.lowercased().contains("mcp-server") || $0.lowercased().hasSuffix("-mcp") }) {
            let known = ["maestro", "playwright", "chrome", "github", "sentry", "slack", "supabase"]
            let joined = launch.argv.joined(separator: " ").lowercased()
            let name = known.first { joined.contains($0) }.map { $0.capitalized } ?? proc.name
            return (.mcp, "\(name) MCP server")
        }
        // An interpreter is named by what it runs: "node vite", not "node".
        let interpreters: Set<String> = ["node", "bun", "deno", "python", "python3", "ruby", "java"]
        if interpreters.contains(proc.name), launch.argv.count > 1 {
            let script = launch.argv.dropFirst().first { !$0.hasPrefix("-") && !$0.contains("*") } ?? ""
            let short = (script as NSString).lastPathComponent
            if !short.isEmpty { return (.background, "\(proc.name) \(short)") }
        }
        return (.background, proc.name)
    }

    /// Processes a Runway seat started that macOS has since adopted: parent
    /// is launchd, the seat's tag is still in their environment. Apps are
    /// left out, since an app opened from a terminal inherits the tag too
    /// (Ghostty, a browser helper) without being the seat's work.
    nonisolated private static func leftovers(
        all: [pid_t: Proc],
        children: [pid_t: [pid_t]],
        usage: (Proc) -> Usage
    ) -> [Leftover] {
        let me = getuid()
        var found: [Leftover] = []
        for proc in all.values where proc.ppid == 1 && proc.uid == me {
            let launch = arguments(of: proc.pid)
            guard launch.env["RUNWAY_CONTROL"] != nil, !launch.exec.contains(".app/Contents/") else { continue }
            var pids: [pid_t] = []
            var queue = [proc.pid]
            while let pid = queue.popLast() {
                pids.append(pid)
                queue.append(contentsOf: children[pid] ?? [])
            }
            let total = pids.compactMap { all[$0] }.reduce(Usage()) { $0 + usage($1) }
            let (label, shared) = leftoverName(proc, launch: launch)
            found.append(Leftover(
                id: proc.pid,
                label: label,
                startedBy: launch.env["RUNWAY_SESSION_NAME"] ?? launch.env["RUNWAY_AGENT_NAME"] ?? "a Runway terminal",
                flight: launch.env["RUNWAY_FLIGHT"].flatMap { Int($0) },
                shared: shared,
                pids: pids,
                usage: total
            ))
        }
        return found.sorted { $0.usage.memory > $1.usage.memory }
    }

    /// What to call a leftover, and whether every flight shares it.
    nonisolated private static func leftoverName(
        _ proc: Proc,
        launch: (exec: String, argv: [String], env: [String: String])
    ) -> (String, Bool) {
        let path = launch.exec.lowercased()
        if path.contains("/emulator/"), !path.contains("qemu-system") {
            return ("Android emulator helper", true)
        }
        if path.contains("qemu-system") {
            let avd = launch.argv.firstIndex(of: "-avd").flatMap { index in
                launch.argv.indices.contains(index + 1) ? launch.argv[index + 1] : nil
            }
            return ("Android emulator" + (avd.map { " (\($0))" } ?? ""), true)
        }
        if proc.name == "adb" { return ("adb server", true) }
        if path.contains("simulator") || path.contains("simctl") || path.contains("coresimulator") {
            return ("iOS simulator", true)
        }
        let (_, label) = describe(proc, launch: launch)
        return (label, false)
    }

    /// Seats (by control id) whose Claude has a shell running under it: a
    /// command it left going in the background, a watcher, a dev server.
    /// That is Claude's own "1 shell still running", seen from outside.
    nonisolated static func seatsWithShells() -> Set<String> {
        let all = allProcesses()
        var children: [pid_t: [pid_t]] = [:]
        for proc in all.values { children[proc.ppid, default: []].append(proc.pid) }
        var tree: [pid_t] = []
        var queue = [getpid()]
        while let pid = queue.popLast() {
            tree.append(pid)
            queue.append(contentsOf: children[pid] ?? [])
        }
        var found: Set<String> = []
        for pid in tree {
            guard let proc = all[pid] else { continue }
            let hasShell = (children[pid] ?? []).contains { child in
                all[child].map { shells.contains($0.name) } ?? false
            }
            guard hasShell else { continue }
            let launch = arguments(of: pid)
            guard case (.claude, _) = describe(proc, launch: launch),
                  let control = launch.env["RUNWAY_CONTROL"] else { continue }
            found.insert(URL(fileURLWithPath: control).deletingPathExtension().lastPathComponent)
        }
        return found
    }

    /// Ask these processes to quit, and make them a few seconds later if
    /// they have not.
    nonisolated static func quit(_ pids: [Int32]) {
        for pid in pids { kill(pid, SIGTERM) }
        DispatchQueue.global().asyncAfter(deadline: .now() + 3) {
            for pid in pids where kill(pid, 0) == 0 { kill(pid, SIGKILL) }
        }
    }

    /// After a flight is stopped: close whatever its seats started that is
    /// still running, attached or not, except what every flight shares.
    /// Waits a moment first, so the terminals' own hang-up lands and only
    /// what ignored it is left.
    nonisolated static func cleanUp(seats: Set<String>) {
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 1.5) {
            let me = getuid()
            let all = allProcesses()
            /// Started inside another app (a Ghostty window opened from a
            /// seat inherits its tag), so it is that app's, not the seat's.
            func insideAnotherApp(_ pid: pid_t) -> Bool {
                var parent = all[pid]?.ppid ?? 1
                while parent > 1, let proc = all[parent] {
                    if parent == getpid() { return false }
                    if arguments(of: parent).exec.contains(".app/Contents/") { return true }
                    parent = proc.ppid
                }
                return false
            }
            var doomed: [Int32] = []
            for proc in all.values where proc.uid == me && proc.pid != getpid() {
                let launch = arguments(of: proc.pid)
                guard let control = launch.env["RUNWAY_CONTROL"],
                      !launch.exec.contains(".app/Contents/") else { continue }
                let seat = URL(fileURLWithPath: control).deletingPathExtension().lastPathComponent
                guard seats.contains(seat), !leftoverName(proc, launch: launch).1,
                      !insideAnotherApp(proc.pid) else { continue }
                doomed.append(proc.pid)
            }
            if !doomed.isEmpty {
                NSLog("Runway: closing \(doomed.count) process(es) the stopped flight left running")
                quit(doomed)
            }
        }
    }

    /// The whole Mac's CPU in use since the last sample, all cores together.
    nonisolated private static func cpuTicks() -> [UInt32] {
        var load = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &load) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return [] }
        let t = load.cpu_ticks
        return [t.0, t.1, t.2, t.3]   // user, system, idle, nice
    }

    nonisolated private static func macCPU(_ now: [UInt32], since before: [UInt32]) -> Double {
        guard now.count == 4, before.count == 4 else { return 0 }
        let delta = zip(now, before).map { Double($0 &- $1) }
        let total = delta.reduce(0, +)
        guard total > 0 else { return 0 }
        return (delta[0] + delta[1] + delta[3]) / total * 100
    }

    nonisolated private static let timebase: (numer: UInt32, denom: UInt32) = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return (info.numer, info.denom)
    }()

    /// Every process, with its parent from the kernel's process table, which
    /// any user may read. `proc_pidinfo` refuses processes owned by root, and
    /// every terminal hangs off a root-owned `/usr/bin/login`, so asking it
    /// for parents lost every agent below Runway.
    nonisolated private static func allProcesses() -> [pid_t: Proc] {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0]
        var size = 0
        guard sysctl(&mib, 4, nil, &size, nil, 0) == 0, size > 0 else { return [:] }
        size += size / 8
        let stride = MemoryLayout<kinfo_proc>.stride
        var table = [kinfo_proc](repeating: kinfo_proc(), count: size / stride)
        guard sysctl(&mib, 4, &table, &size, nil, 0) == 0 else { return [:] }
        var found: [pid_t: Proc] = [:]
        for entry in table.prefix(size / stride) {
            let pid = entry.kp_proc.p_pid
            guard pid > 0 else { continue }
            var usage = rusage_info_v2()
            let ok = withUnsafeMutablePointer(to: &usage) { pointer in
                pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                    proc_pid_rusage(pid, RUSAGE_INFO_V2, $0) == 0
                }
            }
            let ticks = ok ? usage.ri_user_time + usage.ri_system_time : 0
            let nanos = ticks * UInt64(timebase.numer) / UInt64(max(1, timebase.denom))
            let name = withUnsafeBytes(of: entry.kp_proc.p_comm) { raw in
                String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self)
            }
            found[pid] = Proc(
                pid: pid,
                ppid: entry.kp_eproc.e_ppid,
                uid: entry.kp_eproc.e_ucred.cr_uid,
                name: name,
                memory: ok ? usage.ri_phys_footprint : 0,
                cpuNanos: nanos
            )
        }
        return found
    }

    /// A process's executable, arguments and Runway environment, from the
    /// kernel's copy of what it was started with.
    nonisolated private static func arguments(of pid: pid_t) -> (exec: String, argv: [String], env: [String: String]) {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > 0 else { return ("", [], [:]) }
        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, 3, &buffer, &size, nil, 0) == 0, size > 4 else { return ("", [], [:]) }
        let argc = buffer.withUnsafeBytes { $0.load(as: Int32.self) }
        var index = 4
        func next() -> String {
            let start = index
            while index < size, buffer[index] != 0 { index += 1 }
            let text = String(decoding: buffer[start..<min(index, size)], as: UTF8.self)
            index += 1
            return text
        }
        let exec = next()
        while index < size, buffer[index] == 0 { index += 1 }
        var argv: [String] = []
        while index < size, argv.count < Int(argc) { argv.append(next()) }
        var env: [String: String] = [:]
        while index < size {
            if buffer[index] == 0 { break }
            let entry = next()
            if entry.hasPrefix("RUNWAY_"), let equals = entry.firstIndex(of: "=") {
                env[String(entry[..<equals])] = String(entry[entry.index(after: equals)...])
            }
        }
        return (exec, argv, env)
    }

    /// Memory in use across the Mac, as Activity Monitor's "Memory Used":
    /// app memory, wired and compressed.
    nonisolated private static func macMemoryUsed() -> UInt64 {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return 0 }
        let page = UInt64(getpagesize())
        let app = UInt64(stats.internal_page_count) - UInt64(stats.purgeable_count)
        return (app + UInt64(stats.wire_count) + UInt64(stats.compressor_page_count)) * page
    }
}
