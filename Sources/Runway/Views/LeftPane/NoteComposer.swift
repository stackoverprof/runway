import SwiftUI

/// A compact markdown note composer with formatting toolbar.
/// The content is stored as raw markdown text.
struct NoteComposer: View {
    @Binding var isPresented: Bool
    let onPost: (String) -> Void

    @State private var text = ""
    @FocusState private var focused: Bool

    private static let accent = Color(red: 0.45, green: 0.82, blue: 0.78)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Toolbar row
            HStack(spacing: 2) {
                toolButton("bold", label: "B", weight: .bold) { wrap("**") }
                toolButton("italic", label: "I", weight: .regular, italic: true) { wrap("_") }
                toolButton("heading", systemImage: "number") { insertPrefix("## ") }
                toolButton("list", systemImage: "list.bullet") { insertPrefix("- ") }
                toolButton("code", label: "`⁠`", weight: .medium) { wrap("`") }
                toolButton("codeBlock", label: "```", weight: .medium) { wrapBlock("```") }
                Spacer()
                // Character count
                Text("\(text.count)")
                    .font(.system(size: 9.5, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.2))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.white.opacity(0.03))

            // Divider
            Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1)

            // Editor
            TextEditor(text: $text)
                .focused($focused)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(Color.white.opacity(0.85))
                .scrollContentBackground(.hidden)
                .padding(.horizontal, 6)
                .padding(.vertical, 6)
                .frame(minHeight: 100, maxHeight: 180)

            // Divider
            Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1)

            // Bottom action bar
            HStack(spacing: 10) {
                Text("Markdown supported")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.2))
                Spacer()
                Button("Cancel") {
                    withAnimation(.easeInOut(duration: 0.15)) { isPresented = false }
                }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.5))
                .onHover { if $0 { NSCursor.pointingHand.set() } else { NSCursor.arrow.set() } }

                Button {
                    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { return }
                    onPost(trimmed)
                    text = ""
                    withAnimation(.easeInOut(duration: 0.15)) { isPresented = false }
                } label: {
                    Text("Post")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Color.white.opacity(0.3) : Color.black)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 5)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                      ? Color.white.opacity(0.08)
                                      : Self.accent)
                        )
                }
                .buttonStyle(.plain)
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .onHover { if $0 { NSCursor.pointingHand.set() } else { NSCursor.arrow.set() } }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(white: 0.06)))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.08), lineWidth: 1))
        .onAppear { focused = true }
    }

    // MARK: Toolbar helpers

    private func toolButton(_ id: String, label: String? = nil, systemImage: String? = nil,
                            weight: Font.Weight = .medium, italic: Bool = false,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Group {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 11, weight: weight))
                } else if let label {
                    Text(label)
                        .font(.system(size: 11, weight: weight))
                        .italic(italic)
                }
            }
            .foregroundStyle(Color.white.opacity(0.45))
            .frame(width: 26, height: 22)
            .background(RoundedRectangle(cornerRadius: 4).fill(Color.white.opacity(0.04)))
            .contentShape(RoundedRectangle(cornerRadius: 4))
        }
        .buttonStyle(.plain)
        .onHover { if $0 { NSCursor.pointingHand.set() } else { NSCursor.arrow.set() } }
    }

    private func wrap(_ delimiter: String) {
        text += "\(delimiter)text\(delimiter)"
    }

    private func insertPrefix(_ prefix: String) {
        if text.isEmpty || text.hasSuffix("\n") {
            text += prefix
        } else {
            text += "\n\(prefix)"
        }
    }

    private func wrapBlock(_ delimiter: String) {
        if text.isEmpty || text.hasSuffix("\n") {
            text += "\(delimiter)\n\n\(delimiter)\n"
        } else {
            text += "\n\(delimiter)\n\n\(delimiter)\n"
        }
    }
}
