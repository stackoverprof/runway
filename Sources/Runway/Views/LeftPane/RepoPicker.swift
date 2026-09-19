import SwiftUI

struct RepoPicker: View {
    let repos: [String]
    let current: String
    let onPick: (String) -> Void
    @State private var query = ""
    @State private var highlighted = 0
    @FocusState private var searchFocused: Bool

    private var filtered: [String] {
        query.isEmpty ? repos : repos.filter { $0.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").font(.system(size: 11)).foregroundStyle(.secondary)
                TextField("Search cloned repositories", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12.5))
                    .focused($searchFocused)
                    .onSubmit { pickHighlighted() }
                    .onKeyPress(.upArrow) { move(-1); return .handled }
                    .onKeyPress(.downArrow) { move(1); return .handled }
            }
            .padding(.horizontal, 12).padding(.vertical, 9)
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(filtered.enumerated()), id: \.element) { index, r in
                            Button { onPick(r) } label: {
                                HStack(spacing: 8) {
                                    Text(r)
                                        .font(.system(size: 12.5, design: .monospaced))
                                        .foregroundStyle(.primary)
                                        .lineLimit(1).truncationMode(.middle)
                                    Spacer(minLength: 8)
                                    if r == current {
                                        Image(systemName: "checkmark").font(.system(size: 10, weight: .bold))
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .padding(.horizontal, 12).padding(.vertical, 7)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(index == highlighted ? Color.primary.opacity(0.1) : Color.clear)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .pointerCursor()
                            .id(r)
                        }
                        if filtered.isEmpty {
                            Text(repos.isEmpty ? "No cloned repositories found." : "No matches.")
                                .font(.system(size: 12)).foregroundStyle(.secondary)
                                .padding(12)
                        }
                    }
                }
                .frame(maxHeight: 320)
                .onChange(of: highlighted) { _, index in
                    guard filtered.indices.contains(index) else { return }
                    proxy.scrollTo(filtered[index])
                }
            }
        }
        .frame(width: 270)
        .onAppear {
            searchFocused = true
            highlighted = filtered.firstIndex(of: current) ?? 0
        }
        .onChange(of: query) { _, _ in highlighted = 0 }
        .onChange(of: repos) { _, _ in
            highlighted = min(highlighted, max(filtered.count - 1, 0))
        }
    }

    private func move(_ delta: Int) {
        guard !filtered.isEmpty else { return }
        highlighted = min(max(highlighted + delta, 0), filtered.count - 1)
    }

    private func pickHighlighted() {
        guard filtered.indices.contains(highlighted) else { return }
        onPick(filtered[highlighted])
    }
}

struct Chip: View {
    let text: String; let tint: Color
    init(_ text: String, tint: Color) { self.text = text; self.tint = tint }
    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .medium, design: .monospaced))
            .foregroundStyle(tint)
            .lineLimit(1)
            .padding(.horizontal, 7).padding(.vertical, 2.5)
            .background(RoundedRectangle(cornerRadius: 5).fill(tint.opacity(0.14)))
            .overlay(RoundedRectangle(cornerRadius: 5).stroke(tint.opacity(0.25), lineWidth: 1))
    }
}
