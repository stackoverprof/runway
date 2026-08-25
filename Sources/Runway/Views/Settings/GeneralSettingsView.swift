import SwiftUI
import ServiceManagement
import AppKit
import UniformTypeIdentifiers

struct GeneralSettings: View {
    @AppStorage(SettingsKey.pollInterval)  private var pollInterval = 45
    @AppStorage(SettingsKey.idleMinutes)   private var idleMinutes = 30
    @AppStorage(SettingsKey.officeHours)   private var officeHours = 6
    @AppStorage(SettingsKey.hideBots)      private var hideBots = true
    @AppStorage(SettingsKey.fireThreshold)  private var fireThreshold = 5
    @AppStorage(SettingsKey.soundEnabled)  private var soundEnabled = true
    @AppStorage(SettingsKey.alertSound)    private var alertSound = "Glass"
    @AppStorage(SettingsKey.confirmQuit)   private var confirmQuit = true
    @AppStorage(SettingsKey.agentCommandEnabled) private var agentCommandEnabled = false
    @AppStorage(SettingsKey.agentCommand)  private var agentCommand = "claude"
    @AppStorage(SettingsKey.issueAgentSessionsEnabled) private var issueAgentSessionsEnabled = false
    @AppStorage(SettingsKey.brandHeaderStyle) private var brandHeaderStyle = "text"
    @AppStorage(SettingsKey.brandTitle) private var brandTitle = "Activity"
    @AppStorage(SettingsKey.brandLogoFilename) private var brandLogoFilename = ""
    @AppStorage(SettingsKey.terminalFontFamily) private var terminalFontFamily = TerminalFont.defaultFamily
    @AppStorage(SettingsKey.terminalFontSize) private var terminalFontSize = TerminalFont.defaultSize
    @AppStorage(SettingsKey.quickTerminalDirectory) private var quickTerminalDirectory = ""
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var cacheCleared = false
    @State private var issueOrderReset = false
    @State private var brandingError: String?
    @State private var agentCommandChoice = "claude"
    @State private var customFontFamily = ""
    @State private var usingCustomFont = false

    private let sounds = ["Glass", "Ping", "Submarine", "Hero", "Pop", "Funk", "Blow"]
    var body: some View {
        Form {
            Section("Activity feed") {
                Picker("Refresh every", selection: $pollInterval) {
                    Text("15 seconds").tag(15)
                    Text("30 seconds").tag(30)
                    Text("45 seconds").tag(45)
                    Text("1 minute").tag(60)
                    Text("2 minutes").tag(120)
                }
                .pointerCursor()
                Stepper("Active within: \(idleMinutes) min", value: $idleMinutes, in: 5...120, step: 5)
                    .pointerCursor()
                Stepper("On fire threshold: \(fireThreshold) events", value: $fireThreshold, in: 2...20)
                    .pointerCursor()
                Picker("Show people active in the last", selection: $officeHours) {
                    Text("3 hours").tag(3)
                    Text("6 hours").tag(6)
                    Text("12 hours").tag(12)
                    Text("24 hours").tag(24)
                }
                .pointerCursor()
                Toggle("Hide bot accounts", isOn: $hideBots)
                    .pointerCursor()
            }

            Section("Branding") {
                Picker("Header", selection: $brandHeaderStyle) {
                    Text("Text").tag("text")
                    Text("Image").tag("image")
                }
                .pickerStyle(.segmented)
                .pointerCursor()

                if brandHeaderStyle == "text" {
                    TextField("Title", text: $brandTitle)
                } else {
                    HStack(spacing: 8) {
                        Button(brandLogoFilename.isEmpty ? "Choose Logo…" : "Change Logo…") {
                            chooseLogo()
                        }
                        .pointerCursor()
                        if !brandLogoFilename.isEmpty {
                            Button("Remove Logo", role: .destructive) {
                                BrandingManager.removeLogo(named: brandLogoFilename)
                                brandLogoFilename = ""
                                brandingError = nil
                            }
                            .pointerCursor()
                        }
                    }
                }

                HStack(spacing: 12) {
                    Text("Preview")
                        .foregroundStyle(.secondary)
                    Spacer()
                    brandingPreview
                }

                if brandHeaderStyle != "text" || brandTitle != "Activity" || !brandLogoFilename.isEmpty {
                    Button("Restore Default", role: .destructive) {
                        BrandingManager.removeLogo(named: brandLogoFilename)
                        brandLogoFilename = ""
                        brandTitle = "Activity"
                        brandHeaderStyle = "text"
                        brandingError = nil
                    }
                    .pointerCursor()
                }

                Text("Replaces the Activity title in the left pane with custom text or any image format macOS can open, including SVG, PNG, and JPEG.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let brandingError {
                    Text(brandingError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            Section("Notifications") {
                Toggle("Play a sound when an agent needs attention", isOn: $soundEnabled)
                    .pointerCursor()
                HStack {
                    Picker("Alert sound", selection: $alertSound) {
                        ForEach(sounds, id: \.self) { Text($0).tag($0) }
                    }
                    .disabled(!soundEnabled)
                    .pointerCursor()
                    Button("Test") { RunwayNotificationManager.playSelectedSound() }
                        .disabled(!soundEnabled)
                        .pointerCursor()
                }
            }

            Section("Terminal") {
                Picker("Font", selection: fontSelection) {
                    ForEach(TerminalFont.selectableFamilies(current: terminalFontFamily), id: \.self) { family in
                        Text(family).tag(family)
                    }
                    Divider()
                    Text("Custom\u{2026}").tag(Self.customFontTag)
                }
                .pointerCursor()

                if usingCustomFont {
                    TextField("Font family", text: $customFontFamily)
                        .onSubmit { applyCustomFont() }
                    Text(customFontNotice)
                        .font(.caption)
                        .foregroundStyle(
                            TerminalFont.isInstalled(terminalFontFamily)
                                ? Color.secondary
                                : Color.orange
                        )
                }

                Stepper("Size: \(terminalFontSize)pt", value: $terminalFontSize, in: TerminalFont.sizeRange)
                    .pointerCursor()

                terminalFontPreview

                if terminalFontFamily != TerminalFont.defaultFamily
                    || terminalFontSize != TerminalFont.defaultSize {
                    Button("Restore Default", role: .destructive) {
                        terminalFontFamily = TerminalFont.defaultFamily
                        terminalFontSize = TerminalFont.defaultSize
                        usingCustomFont = false
                    }
                    .pointerCursor()
                }

                Text("Applies to every open terminal straight away. Your own Ghostty config is never modified.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Quick terminal") {
                HStack(spacing: 8) {
                    TextField(
                        "Start in",
                        text: $quickTerminalDirectory,
                        prompt: Text("Last used directory")
                    )
                    Button("Choose\u{2026}") { chooseQuickDirectory() }
                        .pointerCursor()
                }

                if let quickDirectoryWarning {
                    Text(quickDirectoryWarning)
                        .font(.caption)
                        .foregroundStyle(.orange)
                }

                if !quickTerminalDirectory.isEmpty {
                    Button("Restore Default", role: .destructive) {
                        quickTerminalDirectory = ""
                    }
                    .pointerCursor()
                }

                Text("The quick terminal (\u{2318}\u{2325}Q) opens here every time its shell starts. Leave it empty to reopen wherever the last shell was left. A leading tilde is expanded.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Agents") {
                Toggle("Run command in each agent", isOn: $agentCommandEnabled)
                    .pointerCursor()
                Picker("Command", selection: $agentCommandChoice) {
                    Text("Claude").tag("claude")
                    Text("Codex").tag("codex")
                    Text("Agent").tag("agent")
                    Text("Custom…").tag("custom")
                }
                    .disabled(!agentCommandEnabled)
                    .pointerCursor()

                if agentCommandChoice == "custom" {
                    TextField("Custom command", text: $agentCommand)
                        .disabled(!agentCommandEnabled)
                }

                Text("Runs automatically when a Focus terminal opens, when you reopen the app, and in the quick terminal. Leave unchecked for a plain shell.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Toggle("Resume Focus conversations (Experimental)", isOn: $issueAgentSessionsEnabled)
                    .disabled(!agentCommandEnabled)
                    .pointerCursor()

                Text("Binds each Focus issue to one agent conversation across removal and app relaunch. Tested with Claude only. Other agents and models are experimental and untested. Takes effect when a terminal starts.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Issue boards") {
                HStack {
                    Button("Reset Open & Closed Order", role: .destructive) {
                        AssignedIssues.resetSavedBacklogOrder()
                        issueOrderReset = true
                    }
                    .pointerCursor()
                    if issueOrderReset {
                        Text("Reset")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Text("Restores the default GitHub ordering for Open and Closed issues. Focus membership and Focus order are not changed.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("General") {
                Toggle("Confirm before quitting", isOn: $confirmQuit)
                    .pointerCursor()
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .pointerCursor()
                    .onChange(of: launchAtLogin) { _, on in
                        try? on ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister()
                    }
                HStack {
                    Button("Clear activity-feed cache") {
                        GitHubFeed.clearCache()
                        cacheCleared = true
                    }
                    .pointerCursor()
                    if cacheCleared {
                        Text("Cleared").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            agentCommandChoice = ["claude", "codex", "agent"].contains(agentCommand)
                ? agentCommand
                : "custom"
        }
        .onChange(of: agentCommandChoice) { _, choice in
            guard choice != "custom" else { return }
            agentCommand = choice
        }
        // Rewrite the theme file and push it to every open terminal, so the new
        // face is on screen before the Settings window is even closed.
        .onChange(of: terminalFontFamily) { _, _ in RunwayTerminalHost.reloadTheme() }
        .onChange(of: terminalFontSize) { _, _ in RunwayTerminalHost.reloadTheme() }
    }

    // MARK: Terminal font

    private static let customFontTag = "\u{0}custom"

    /// The picker sits on top of two pieces of state: the stored family, and
    /// whether the user asked to type one in by hand.
    private var fontSelection: Binding<String> {
        Binding(
            get: { usingCustomFont ? Self.customFontTag : terminalFontFamily },
            set: { choice in
                if choice == Self.customFontTag {
                    customFontFamily = terminalFontFamily
                    usingCustomFont = true
                } else {
                    usingCustomFont = false
                    terminalFontFamily = choice
                }
            }
        )
    }

    private func applyCustomFont() {
        terminalFontFamily = TerminalFont.sanitizedFamily(customFontFamily)
    }

    private var customFontNotice: String {
        guard TerminalFont.isInstalled(terminalFontFamily) else {
            return "\(terminalFontFamily) is not installed on this Mac, so the terminal falls back to its default face."
        }
        return "Press Return to apply."
    }

    /// Honest preview: the real family at the real size, on the terminal's own
    /// background. Falls back to the system monospaced face when the family
    /// cannot be instantiated, which is also roughly what the terminal does.
    private var previewFont: Font {
        let size = CGFloat(terminalFontSize)
        if NSFont(name: terminalFontFamily, size: size) != nil {
            return .custom(terminalFontFamily, fixedSize: size)
        }
        return .system(size: size, design: .monospaced)
    }

    private var terminalFontPreview: some View {
        HStack(spacing: 12) {
            Text("Preview")
                .foregroundStyle(.secondary)
            Spacer()
            Text(verbatim: "~/runway % claude --resume 0b6f2b1e")
                .font(previewFont)
                .foregroundStyle(Color(white: 0.90))
                .lineLimit(1)
                .truncationMode(.tail)
                .padding(.horizontal, 10)
                .padding(.vertical, 9)
                .frame(width: 250, alignment: .leading)
                .background(RunwayTerminal.body)
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }

    @ViewBuilder
    private var brandingPreview: some View {
        if brandHeaderStyle == "image",
           let image = BrandingManager.image(named: brandLogoFilename) {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .frame(width: 180, height: 42)
        } else {
            Text(resolvedBrandTitle)
                .font(.system(size: 27, weight: .bold))
                .lineLimit(1)
                .frame(maxWidth: 180, minHeight: 42, alignment: .trailing)
        }
    }

    private var resolvedBrandTitle: String {
        let title = brandTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? "Activity" : title
    }

    // MARK: Quick terminal

    /// Only warn about a path the user actually typed, and only when it is not
    /// a folder here: the quick terminal silently falls back in that case.
    private var quickDirectoryWarning: String? {
        let trimmed = quickTerminalDirectory.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, QuickTerminalDirectory.resolved(trimmed) == nil else {
            return nil
        }
        return "\(trimmed) is not a folder on this Mac, so the quick terminal opens in its last directory."
    }

    private func chooseQuickDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Choose the folder the quick terminal starts in"
        panel.prompt = "Choose Folder"
        if let current = QuickTerminalDirectory.resolved(quickTerminalDirectory) {
            panel.directoryURL = URL(fileURLWithPath: current)
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        quickTerminalDirectory = url.path
    }

    private func chooseLogo() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.image]
        panel.message = "Choose a logo for the Activity pane"
        panel.prompt = "Choose Logo"
        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            brandLogoFilename = try BrandingManager.importLogo(
                from: url,
                replacing: brandLogoFilename
            )
            brandHeaderStyle = "image"
            brandingError = nil
        } catch {
            brandingError = error.localizedDescription
        }
    }

}
