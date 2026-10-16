import SwiftUI

/// The ⌘F box for one tab. It keeps its own text, so a keystroke re-renders
/// only the field. The list it filters hears about the text after a short
/// pause. Holding the text on the whole left pane made every key re-lay out all
/// three tabs and rebuild the issue lists, which is what made typing lag.
struct RunwaySearchField: View {
    let placeholder: String
    @Binding var query: String
    let tab: FeedTab
    var focus: FocusState<FeedTab?>.Binding

    @State private var text = ""

    /// Long enough to cover a burst of keys, short enough to read as live.
    static let commitDelay: UInt64 = 140_000_000

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.30))

            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 10.5, design: .monospaced))
                .foregroundStyle(Color.white.opacity(0.82))
                .focused(focus, equals: tab)
                .onSubmit { query = text }

            if !text.isEmpty {
                Button {
                    text = ""
                    query = ""
                    focus.wrappedValue = tab
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 10.5))
                        .foregroundStyle(Color.white.opacity(0.28))
                }
                .buttonStyle(.plain)
                .pointerCursor()
                .help("Clear search")
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 30)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.035)))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(
                    Color.white.opacity(focus.wrappedValue == tab ? 0.15 : 0.07),
                    lineWidth: 1
                )
        )
        .onAppear { text = query }
        .onChange(of: query) { _, committed in
            // The pane cleared the search (closing it, switching repository).
            if committed.isEmpty, !text.isEmpty { text = "" }
        }
        .task(id: text) {
            guard text != query else { return }
            // Emptying the box restores the full list at once; only narrowing
            // waits for the typing to settle.
            if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                query = text
                return
            }
            do {
                try await Task.sleep(nanoseconds: Self.commitDelay)
            } catch {
                return
            }
            query = text
        }
    }
}
