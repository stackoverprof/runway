import SwiftUI
import AppKit

/// The typeface every terminal uses, and where the quick terminal opens.
struct TerminalSettings: View {
    @AppStorage(SettingsKey.terminalFontFamily) private var terminalFontFamily = TerminalFont.defaultFamily
    @AppStorage(SettingsKey.terminalFontSize) private var terminalFontSize = TerminalFont.defaultSize
    @AppStorage(SettingsKey.quickTerminalDirectory) private var quickTerminalDirectory = ""
    @AppStorage(SettingsKey.quickAutoHide) private var quickAutoHide = true
    @AppStorage(SettingsKey.quickAutoHideSeconds) private var quickAutoHideSeconds = 3
    @AppStorage(SettingsKey.defaultLayoutAxis) private var defaultLayoutAxis = TerminalLayoutAxis.vertical.rawValue
    @AppStorage(SettingsKey.dropRetentionDays) private var dropRetentionDays = 7
    @State private var customFontFamily = ""
    @State private var usingCustomFont = false

    var body: some View {
        Form {
            Section("Font") {
                Picker("Family", selection: fontSelection) {
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

                Toggle("Hide it when it loses focus", isOn: $quickAutoHide)
                    .pointerCursor()
                Stepper(
                    "Hide after: \(quickAutoHideSeconds)s",
                    value: $quickAutoHideSeconds,
                    in: 1...60
                )
                .disabled(!quickAutoHide)
                .pointerCursor()
                Text("Pinning it (the pin in its header) keeps it open whatever this says.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Layout") {
                Picker("New windows open", selection: $defaultLayoutAxis) {
                    Text("Stacked").tag(TerminalLayoutAxis.vertical.rawValue)
                    Text("Side by side").tag(TerminalLayoutAxis.horizontal.rawValue)
                }
                .pickerStyle(.segmented)
                .pointerCursor()
                Text("The accordion direction a window starts in. \u{2318}\u{2325}L still flips it, and a window remembers what you left it on.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Dropped images") {
                Stepper(
                    dropRetentionDays == 0
                        ? "Keep them"
                        : "Delete after: \(dropRetentionDays) day\(dropRetentionDays == 1 ? "" : "s")",
                    value: $dropRetentionDays,
                    in: 0...90
                )
                .pointerCursor()
                Text("An image dragged out of a web page has no file on disk, so Runway writes it into its own folder to hand the path to an agent. Your ~/Downloads is never touched. Zero days keeps them for good.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        // Rewrite the theme file and push it to every open terminal, so the new
        // face is on screen before the Settings window is even closed.
        .onChange(of: terminalFontFamily) { _, _ in RunwayTerminalHost.reloadTheme() }
        .onChange(of: terminalFontSize) { _, _ in RunwayTerminalHost.reloadTheme() }
    }

    // MARK: Font

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
}
