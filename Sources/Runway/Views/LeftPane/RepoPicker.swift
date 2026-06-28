import SwiftUI

struct RepoPicker: View {
    let repos: [String]
    let current: String
    let onPick: (String) -> Void
    @State private var query = ""

    private var filtered: [String] {
        query.isEmpty ? repos : repos.filter { $0.localizedCaseInsensitiveContains(query) }
    }

    /// A typed `owner/repo` that isn't already in the list — lets you open any
    /// repo (e.g. one beyond the fetched 100, or one you don't own).
    private var freeform: String? {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard q.contains("/"), !q.hasPrefix("/"), !q.hasSuffix("/"),
              !q.contains(" "), !repos.contains(q) else { return nil }
        return q
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").font(.system(size: 11)).foregroundStyle(.secondary)
                TextField("Search, or type owner/repo", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12.5))
            }
            .padding(.horizontal, 12).padding(.vertical, 9)
            Divider()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if let f = freeform {
                        Button { onPick(f) } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "arrow.right.circle")
                                    .font(.system(size: 11)).foregroundStyle(.secondary)
                                Text("Open \(f)")
                                    .font(.system(size: 12.5, design: .monospaced))
                                    .foregroundStyle(.primary).lineLimit(1).truncationMode(.middle)
                                Spacer(minLength: 8)
                            }
                            .padding(.horizontal, 12).padding(.vertical, 7)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    ForEach(filtered, id: \.self) { r in
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
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    if filtered.isEmpty, freeform == nil {
                        Text(repos.isEmpty ? "Loading repos…" : "No matches. Type owner/repo to open any repo.")
                            .font(.system(size: 12)).foregroundStyle(.secondary)
                            .padding(12)
                    }
                }
            }
            .frame(maxHeight: 320)
        }
        .frame(width: 270)
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
