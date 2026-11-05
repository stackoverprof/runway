import SwiftUI

/// The "House rules" Settings tab.
///
/// One place for how this Runway works. Every agent is handed these when it
/// starts, so nothing has to be shared, committed, or pasted into a session
/// for a crew to know the conventions it works by.
///
/// The box always holds the rules actually in use, as plain text you can
/// edit. It used to be empty with Runway's rules drawn in grey behind it,
/// plus a "Start from Runway's" and a "Clear", and nobody could tell whether
/// the text on screen was theirs or a placeholder.
struct HouseRulesSettings: View {
    @AppStorage(HouseRules.key) private var saved = ""
    @State private var text = ""

    private static func same(_ a: String, _ b: String) -> Bool {
        a.trimmingCharacters(in: .whitespacesAndNewlines)
            == b.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var edited: Bool { !Self.same(text, HouseRules.fallback) }

    var body: some View {
        Form {
            Section {
                TextEditor(text: $text)
                    .font(.system(size: 12, design: .monospaced))
                    .frame(minHeight: 260)
            } header: {
                Text("Every agent Runway starts is handed these, with its own role card. They are never written into a repository.")
            } footer: {
                HStack(spacing: 8) {
                    if edited {
                        Text("EDITED")
                            .font(.system(size: 9, weight: .semibold, design: .monospaced))
                            .tracking(0.8)
                            .foregroundStyle(.orange)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.orange.opacity(0.15)))
                        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Text("Empty, so agents get Runway's rules.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Text("Runway's rules.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if edited {
                        Button("Reset to Runway's") { text = HouseRules.fallback }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { text = HouseRules.current }
        .onChange(of: text) {
            // Runway's own text, or nothing, is stored as nothing, so a
            // later change to Runway's rules still reaches you.
            saved = Self.same(text, HouseRules.fallback) ? "" : text
        }
    }
}
