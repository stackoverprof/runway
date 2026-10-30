import SwiftUI

/// The "House rules" Settings tab.
///
/// One place for how this Runway works. Every agent is handed these when it
/// starts, so nothing has to be shared, committed, or pasted into a session
/// for a crew to know the conventions it works by.
struct HouseRulesSettings: View {
    @AppStorage(HouseRules.key) private var rules = ""
    @State private var showingReset = false

    var body: some View {
        Form {
            Section {
                TextEditor(text: $rules)
                    .font(.system(size: 12, design: .monospaced))
                    .frame(minHeight: 260)
                    .overlay(alignment: .topLeading) {
                        if rules.isEmpty {
                            Text(HouseRules.fallback)
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 8)
                                .allowsHitTesting(false)
                        }
                    }
            } header: {
                Text("Every agent Runway starts is handed these, with its own role card. They are never written into a repository.")
            } footer: {
                HStack {
                    Text(rules.isEmpty ? "Runway's own rules are in use." : "Your rules are in use.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Start from Runway's") { rules = HouseRules.fallback }
                        .pointerCursor()
                        .disabled(!rules.isEmpty)
                    Button("Clear", role: .destructive) { rules = "" }
                        .pointerCursor()
                        .disabled(rules.isEmpty)
                }
            }
        }
        .formStyle(.grouped)
    }
}
