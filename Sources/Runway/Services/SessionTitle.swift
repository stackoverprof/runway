import Foundation

/// The name a Claude conversation was given with /rename, read from its
/// transcript. Transcripts grow to many megabytes, so each is scanned once and
/// then only from where the last read stopped.
actor SessionTitle {
    static let shared = SessionTitle()

    private struct Scan {
        var offset: UInt64 = 0
        var partial = Data()
        var title: String?
    }

    private var transcripts: [String: URL] = [:]
    private var scans: [URL: Scan] = [:]

    /// The quick tab's conversation name, or nil before it has one.
    func title(forQuickRoot root: String) -> String? {
        guard let data = try? Data(contentsOf: AgentControl.quickProviderSessionFile(root: root)),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let sessionID = json["sessionId"] as? String, !sessionID.isEmpty,
              let transcript = transcript(for: sessionID) else { return nil }
        return title(in: transcript)
    }

    private func transcript(for sessionID: String) -> URL? {
        if let known = transcripts[sessionID] { return known }
        let projects = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/projects")
        let folders = (try? FileManager.default.contentsOfDirectory(
            at: projects,
            includingPropertiesForKeys: nil
        )) ?? []
        for folder in folders {
            let candidate = folder.appendingPathComponent("\(sessionID).jsonl")
            if FileManager.default.fileExists(atPath: candidate.path) {
                transcripts[sessionID] = candidate
                return candidate
            }
        }
        return nil
    }

    private func title(in transcript: URL) -> String? {
        var scan = scans[transcript] ?? Scan()
        guard let handle = try? FileHandle(forReadingFrom: transcript) else { return scan.title }
        defer { try? handle.close() }
        let end = (try? handle.seekToEnd()) ?? 0
        if end < scan.offset { scan = Scan() }   // rewritten from scratch
        guard end > scan.offset else { return scan.title }
        try? handle.seek(toOffset: scan.offset)
        var chunk = scan.partial
        chunk.append(handle.readData(ofLength: Int(end - scan.offset)))
        scan.offset = end

        let marker = Data(#""type":"custom-title""#.utf8)
        var lines = chunk.split(separator: UInt8(ascii: "\n"), omittingEmptySubsequences: false)
        scan.partial = Data(lines.removeLast())
        for line in lines where line.range(of: marker) != nil {
            if let json = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
               let title = (json["customTitle"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
               !title.isEmpty {
                scan.title = title
            }
        }
        scans[transcript] = scan
        return scan.title
    }
}
