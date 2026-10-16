import SwiftUI

struct RepoPicker: View {
    /// One row per clone, titled with the clone's folder name (`monorepo`,
    /// `monosentry`): the same name its Focus agents carry.
    struct Choice: Hashable {
        let repository: String
        let path: String

        var title: String { CloneName.name(ofCheckout: path) }
    }

    let repos: [Choice]
    /// The path of the clone on screen.
    let current: String?
    let onPick: (Choice) -> Void
    @State private var query = ""
    @State private var highlighted = 0
    @FocusState private var searchFocused: Bool

    private var filtered: [Choice] {
        query.isEmpty ? repos : repos.filter {
            SearchText.contains($0.title, query) || SearchText.contains($0.repository, query)
        }
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
                                    Text(r.title)
                                        .font(.system(size: 12.5, design: .monospaced))
                                        .foregroundStyle(.primary)
                                        .lineLimit(1).truncationMode(.middle)
                                    Spacer(minLength: 8)
                                    if r.path == current {
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
                            .id(r.path)
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
                    proxy.scrollTo(filtered[index].path)
                }
            }
        }
        .frame(width: 270)
        .onAppear {
            searchFocused = true
            highlighted = filtered.firstIndex { $0.path == current } ?? 0
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
