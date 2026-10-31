import SwiftUI

/// What a flight does when you are not looking at it, and what it owes
/// before it lands.
struct FlightSettings: View {
    @AppStorage(SettingsKey.seatIdleMinutes) private var seatIdleMinutes = 15
    @AppStorage(SettingsKey.seatsKeptAlive) private var seatsKeptAlive = 12
    @AppStorage(SettingsKey.pilotTerminalPadding) private var pilotTerminalPadding = 9
    @AppStorage(SettingsKey.walkthroughRoot) private var walkthroughRoot = ""
    @AppStorage(SettingsKey.walkthroughSlides) private var walkthroughSlides = 3
    @AppStorage(SettingsKey.askBeforeLandingWithoutEvidence)
    private var askBeforeLanding = true

    var body: some View {
        Form {
            Section("Seats") {
                Stepper(
                    "Let an idle seat go after \(seatIdleMinutes) minutes",
                    value: $seatIdleMinutes,
                    in: 1...240
                )
                Text(
                    "A flight you leave keeps running. Its terminal is let go only "
                    + "once it has been off screen this long and its agent is idle: "
                    + "one that is mid-turn, or waiting on you, is never dropped."
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
