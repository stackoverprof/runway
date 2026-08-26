import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// The left pane's header identity: custom text, or an image of your own.
struct AppearanceSettings: View {
    @AppStorage(SettingsKey.brandHeaderStyle) private var brandHeaderStyle = "text"
    @AppStorage(SettingsKey.brandTitle) private var brandTitle = "Activity"
    @AppStorage(SettingsKey.brandLogoFilename) private var brandLogoFilename = ""
    @State private var brandingError: String?

    var body: some View {
        Form {
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
        }
        .formStyle(.grouped)
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
