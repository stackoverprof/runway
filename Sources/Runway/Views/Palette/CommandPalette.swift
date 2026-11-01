import AppKit
import SwiftUI

/// One thing the palette can do.
struct PaletteItem: Identifiable {
    let id: String
    let icon: String
    let title: String
    let detail: String
    /// What the item is, which is also the heading it sits under.
    let group: String
    /// The chord that does the same thing without the palette, when there is
    /// one. Shown so the palette teaches the keyboard it replaces.
    var chord: String?
    let run: @MainActor () -> Void

    /// Everything a search looks at.
    var haystack: String { "\(title) \(detail) \(group)".lowercased() }
}

/// ⌘K: reach anything by name.
///
/// Numbers run out at nine and a board has twenty flights, so the palette is
/// the other half of the keyboard: the digits are for the flights you know by
/// position, this is for the rest. It lists flights, the crews of the flight
/// you are on, and every verb that did not earn a chord of its own.
struct CommandPalette: View {
    @Bindable var ws: Workspace
    @Bindable var issues: AssignedIssues
    @State private var query = ""
    @State private var picked = 0
    @FocusState private var typing: Bool
    @AppStorage("runway.showLandedCrews") private var showLanded = false

    private var results: [PaletteItem] {
        let all = flights + crews + commands
        let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !needle.isEmpty else { return all }
        let words = needle.split(separator: " ").map(String.init)
        return all.filter { item in
            let hay = item.haystack
            return words.allSatisfy { hay.contains($0) }
        }
    }

    /// Both lanes, the one on screen first: a flight you are looking for is
    /// usually open, but a landed one is still worth reaching.
    private var flights: [PaletteItem] {
        let lanes = ws.runwayIssueTab == .open
            ? [(issues.open, "Flight"), (issues.closed, "Landed flight")]
            : [(issues.closed, "Landed flight"), (issues.open, "Flight")]
        return lanes.flatMap { lane, group in
            lane.enumerated().map { index, flight in
                PaletteItem(
                    id: "flight-\(flight.number)",
                    icon: flight.isClosed ? "checkmark.circle.fill" : "airplane",
                    title: flight.title,
                    detail: detail(for: flight),
                    group: group,
                    chord: group == "Flight" && index < 9 ? "⌘\(index + 1)" : nil
                ) {
                    if flight.isClosed { ws.runwayIssueTab = .closed }
                    FlightRoster.fly(flight, ws: ws)
                }
            }
        }
    }

    private func detail(for flight: AssignedIssue) -> String {
        let reference = GitHubNumber.reference(flight.number)
        guard flight.isFlight else { return reference }
        return "\(reference) · \(flight.landedLegs)/\(flight.legs.count) landed"
    }

    private var crews: [PaletteItem] {
        let flight = issues.issue(ws.flightNumber)
        let onScreen = FlightCrews.flying(in: issues, flight: ws.flightNumber).map(\.number)
        return FlightCrews.all(in: issues, flight: ws.flightNumber).map { crew in
            let place = onScreen.firstIndex(of: crew.number)
            return PaletteItem(
                id: "crew-\(crew.number)",
                icon: crew.isClosed ? "checkmark.circle.fill" : "person.fill",
                title: crew.title,
                detail: [
                    GitHubNumber.reference(crew.number),
                    flight.map { "crew of \(GitHubNumber.reference($0.number))" } ?? "",
                ].filter { !$0.isEmpty }.joined(separator: " · "),
                group: "Crew",
                chord: place.map { $0 < 9 ? "⌘⌃\($0 + 1)" : nil } ?? nil
            ) {
                FlightCrews.read(crew, in: issues, ws: ws)
            }
        }
    }

    private var commands: [PaletteItem] {
        var items: [PaletteItem] = FlightSection.allCases.enumerated().map { index, section in
            PaletteItem(
                id: "section-\(section.rawValue)",
                icon: "rectangle.3.group",
                title: "Show \(section.rawValue)",
                detail: "the middle pane",
                group: "Command",
                chord: index == 0 ? "⌘⌥←" : (index == FlightSection.allCases.count - 1 ? "⌘⌥→" : nil)
            ) {
                ws.selectSection(index: index)
            }
        }
        items.append(PaletteItem(
            id: "atc",
            icon: "chevron.left.forwardslash.chevron.right",
            title: ws.quickVisible ? "Hide the ATC panel" : "Show the ATC panel",
            detail: "the quick terminal",
            group: "Command",
            chord: KeyBindings.shared.chord(for: .quickTerminal).display
        ) { ws.toggleQuick() })
        items.append(PaletteItem(
            id: "landed-crews",
            icon: "chevron.down",
            title: showLanded ? "Fold the landed crews away" : "Show the landed crews",
            detail: "the crew pane",
            group: "Command"
        ) { showLanded.toggle() })
        items.append(PaletteItem(
            id: "lane",
            icon: "arrow.left.arrow.right",
            title: ws.runwayIssueTab == .open ? "Show landed flights" : "Show open flights",
            detail: "the flight list",
            group: "Command"
        ) {
            ws.runwayIssueTab = ws.runwayIssueTab == .open ? .closed : .open
        })
        items.append(PaletteItem(
            id: "repo",
            icon: "shippingbox",
            title: "Switch repository",
            detail: issues.repository ?? "",
            group: "Command",
            chord: KeyBindings.shared.chord(for: .repoPicker).display
        ) { ws.requestRepoPicker() })
        items.append(PaletteItem(
            id: "refresh",
            icon: "arrow.clockwise",
            title: "Refresh this tab",
            detail: ws.selectedTab.rawValue,
            group: "Command"
        ) { ws.requestTabReset() })
        return items
    }

    var body: some View {
        ZStack(alignment: .top) {
            // Anywhere outside the card dismisses it.
            Color.black.opacity(0.35)
                .ignoresSafeArea()
                .onTapGesture { close() }

            card
                .frame(maxWidth: 560)
                .padding(.top, 96)
        }
        .environment(\.colorScheme, .dark)
        .transition(.opacity)
        .onAppear { typing = true }
        .onChange(of: query) { picked = 0 }
    }

    private var card: some View {
        VStack(spacing: 0) {
            field
            if !results.isEmpty {
                Divider().overlay(Color.white.opacity(0.08))
                list
            } else {
                Text("Nothing matches")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.white.opacity(0.3))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
            }
        }
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.black.opacity(0.55)))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.12), lineWidth: 1))
        .shadow(color: .black.opacity(0.5), radius: 30, y: 12)
    }

    private var field: some View {
        HStack(spacing: 9) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.35))
            TextField("Flight, crew, or command", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .foregroundStyle(Color.white.opacity(0.92))
                .focused($typing)
                .onSubmit(runPicked)
                .onKeyPress(.upArrow) { move(-1); return .handled }
                .onKeyPress(.downArrow) { move(1); return .handled }
                .onKeyPress(.escape) { close(); return .handled }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private var list: some View {
        ScrollViewReader { scroll in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    ForEach(Array(results.enumerated()), id: \.element.id) { index, item in
                        if index == 0 || results[index - 1].group != item.group {
                            Text(item.group.uppercased())
                                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                                .foregroundStyle(Color.white.opacity(0.26))
                                .padding(.horizontal, 14)
                                .padding(.top, index == 0 ? 8 : 12)
                                .padding(.bottom, 3)
                        }
                        row(item, chosen: index == picked)
                            .id(item.id)
                            .onTapGesture {
                                picked = index
                                runPicked()
                            }
                    }
                }
                .padding(.bottom, 8)
            }
            .frame(maxHeight: 360)
            .onChange(of: picked) {
                guard results.indices.contains(picked) else { return }
                scroll.scrollTo(results[picked].id, anchor: .center)
            }
        }
    }

    private func row(_ item: PaletteItem, chosen: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: item.icon)
                .font(.system(size: 10))
                .foregroundStyle(Color.white.opacity(chosen ? 0.7 : 0.35))
                .frame(width: 16)
            Text(item.title)
                .font(.system(size: 12.5, weight: chosen ? .medium : .regular))
                .foregroundStyle(Color.white.opacity(chosen ? 0.95 : 0.7))
                .lineLimit(1)
            Text(item.detail)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(Color.white.opacity(0.3))
                .lineLimit(1)
            Spacer(minLength: 8)
            if let chord = item.chord {
                Text(chord)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.32))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(chosen ? Color.white.opacity(0.09) : .clear)
        .contentShape(Rectangle())
        .pointerCursor()
    }

    private func move(_ delta: Int) {
        guard !results.isEmpty else { return }
        picked = min(max(picked + delta, 0), results.count - 1)
    }

    private func runPicked() {
        guard results.indices.contains(picked) else { return }
        let item = results[picked]
        close()
        item.run()
    }

    private func close() {
        ws.paletteVisible = false
    }
}
