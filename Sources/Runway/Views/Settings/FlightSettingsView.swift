import SwiftUI

/// What a flight does when you are not looking at it, and what it owes
/// before it lands.
struct FlightSettings: View {
    @AppStorage(FlightDozer.pinnedKey) private var idlePinned = 30
    @AppStorage(FlightDozer.otherKey) private var idleOther = 15
    @AppStorage(SettingsKey.seatsKeptAlive) private var seatsKeptAlive = 12
    @AppStorage(SettingsKey.pilotTerminalPadding) private var pilotTerminalPadding = 9
    @AppStorage(SettingsKey.walkthroughRoot) private var walkthroughRoot = ""
    @AppStorage(SettingsKey.walkthroughSlides) private var walkthroughSlides = 3
    @AppStorage(SettingsKey.askBeforeLandingWithoutEvidence)
    private var askBeforeLanding = true
    @AppStorage(SeatDirectory.perSeatKey) private var seatDirectories = true

    @AppStorage(FlightSort.key) private var flightSort = FlightSort.free.rawValue

    var body: some View {
        Form {
            Section("Flight list") {
                Picker("Sort flights", selection: $flightSort) {
                    ForEach(FlightSort.allCases, id: \.rawValue) { sort in
                        Text(sort.label).tag(sort.rawValue)
                    }
                }
                Text(
                    "Applies to the flights below the pin line. Recency is the flight "
                    + "you last opened or typed into (its pilot or any crew), re-sorted "
                    + "a few seconds after you stop; a new flight stays near the top "
                    + "for its first 5 minutes. Pinned flights (right-click a card) "
                    + "always sit on top and are always dragged by hand."
                )
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            }

            Section("Seats") {
                Stepper("Stop a quiet pinned flight after \(idlePinned) minutes", value: $idlePinned, in: 5...480, step: 5)
                Stepper("Stop any other quiet flight after \(idleOther) minutes", value: $idleOther, in: 5...480, step: 5)
                Text(
                    "When a flight's pilot, copilot and every crew have all been idle "
                    + "this long, and nobody has typed into them, their Claude sessions "
                    + "are stopped. The flight on screen never is. Opening the flight, or "
                    + "a pilot raising a crew, starts them again where they left off."
                )
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

                Stepper("Keep at most \(seatsKeptAlive) seats alive", value: $seatsKeptAlive, in: 2...40)
                Text("A soft cap. A busy agent is kept even when the pool is over it.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

                Stepper(
                    "Pilot terminal padding: \(pilotTerminalPadding)pt",
                    value: $pilotTerminalPadding,
                    in: 0...24
                )
                Text("Room around the pilot's and copilot's terminals. Crews and the ATC panel keep their own tighter fit.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Section("Evidence") {
                HStack {
                    TextField("~/Developer/walkthrough", text: $walkthroughRoot)
                        .textFieldStyle(.roundedBorder)
                    Button("Choose…") { pickFolder() }
                }
                Text(
                    "Where walkthrough slides are written and read, one folder per "
                    + "issue. Runway passes this to the agents, so the renderer and "
                    + "the publisher follow it too."
                )
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

                Stepper("Slides per walkthrough: \(walkthroughSlides)", value: $walkthroughSlides, in: 1...8)
                Text("What a seat makes unless you name a number.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

                Toggle("Ask before landing a flight with no walkthrough", isOn: $askBeforeLanding)
                Text("Closing is never blocked, only questioned once.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

                Toggle("Open each seat where its work is", isOn: $seatDirectories)
                Text(
                    "A crew starts in its issue's worktree when one exists; a pilot "
                    + "starts in the folder holding every checkout of the repository. "
                    + "Off, every seat starts in the main checkout."
                )
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func pickFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Use folder"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        walkthroughRoot = url.path
    }
}
