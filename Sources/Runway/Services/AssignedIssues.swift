import Foundation

/// One crew of a flight: a sub-issue of the issue being flown.
struct IssueLeg: Codable, Identifiable, Sendable, Equatable {
    let number: Int
    var title: String
    var state: String
    var url: URL
    /// Named only when the leg lives in another repository than its flight.
    var repository: String?

    var id: Int { number }
    var isClosed: Bool { state == "CLOSED" }
}

/// One issue assigned to you in the repository on screen. An issue with
/// sub-issues is a flight, and those sub-issues are its crews.
struct AssignedIssue: Codable, Identifiable, Sendable, Equatable {
    let number: Int
    var title: String
    var state: String
    var closedAt: Date?
    let createdAt: Date?
    let updatedAt: Date?
    let url: URL
    /// The issue's own text, which carries its Acceptance, its Progress and
    /// the conversation it lives in.
    var body: String = ""
    /// The flight this issue is a crew of, when it is one.
    var parent: Int?
    var legs: [IssueLeg] = []

    var id: Int { number }
    var isClosed: Bool { state == "CLOSED" }
    var isFlight: Bool { !legs.isEmpty }
    var landedLegs: Int { legs.filter(\.isClosed).count }

    init(
        number: Int,
        title: String,
        state: String,
        closedAt: Date? = nil,
        createdAt: Date? = nil,
        updatedAt: Date? = nil,
        url: URL,
        body: String = "",
        parent: Int? = nil,
        legs: [IssueLeg] = []
    ) {
        self.number = number
        self.title = title
        self.state = state
        self.closedAt = closedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.url = url
        self.body = body
        self.parent = parent
        self.legs = legs
    }

    /// GitHub's issue list knows nothing of crews, and a cache written before
    /// they existed has none either, so both decode as a flight with no crews
    /// rather than failing the whole list.
    init(from decoder: Decoder) throws {
        let fields = try decoder.container(keyedBy: CodingKeys.self)
        number = try fields.decode(Int.self, forKey: .number)
        title = try fields.decode(String.self, forKey: .title)
        state = try fields.decode(String.self, forKey: .state)
        closedAt = try fields.decodeIfPresent(Date.self, forKey: .closedAt)
        createdAt = try fields.decodeIfPresent(Date.self, forKey: .createdAt)
        updatedAt = try fields.decodeIfPresent(Date.self, forKey: .updatedAt)
        url = try fields.decode(URL.self, forKey: .url)
        body = try fields.decodeIfPresent(String.self, forKey: .body) ?? ""
        parent = try fields.decodeIfPresent(Int.self, forKey: .parent)
        legs = try fields.decodeIfPresent([IssueLeg].self, forKey: .legs) ?? []
    }

    static func matchesSearchQuery(
        _ query: String,
        issue: AssignedIssue,
        repositoryName: String
    ) -> Bool {
        let searchableText = "\(GitHubNumber.reference(issue.number)) \(issue.title) \(repositoryName)"
        return SearchText.containsAllTokens(of: query, in: searchableText)
    }
}

/// Your assigned issues, open and closed, per repository. Cached on disk so a
/// relaunch shows the last list before GitHub answers.
@MainActor @Observable final class AssignedIssues {
    private(set) var issues: [AssignedIssue] = []
    private(set) var loading = false
    private(set) var error: String?
    private(set) var hasSnapshot = false

    private struct Snapshot: Codable {
        var issues: [AssignedIssue]
        var fetchedAt: Date
    }

    /// The repository this board was read from.
    private(set) var repository: String?
    @ObservationIgnored private var loadedRepository: String?
    @ObservationIgnored private var loadTask: Task<Void, Never>?
    @ObservationIgnored private var snapshots = AssignedIssues.readSnapshots()

    /// The flight on screen, if it is still one of yours.
    func issue(_ number: Int?) -> AssignedIssue? {
        guard let number else { return nil }
        return issues.first { $0.number == number }
    }

    /// The flights, newest first. A crew belongs to its flight's pane, not
    /// to this list, so an issue with a parent is left out of both.
    /// Flights in the order you arranged them on the board, with any you have
    /// not placed yet at the top, newest first.
    var open: [AssignedIssue] {
        let flights = issues.filter { !$0.isClosed && $0.parent == nil }
        guard let repository else { return flights.sorted { $0.number > $1.number } }
        return FlightBoard.shared.ordered(flights, in: repository)
    }

    var closed: [AssignedIssue] {
        issues.filter { $0.isClosed && $0.parent == nil }
            .sorted { ($0.closedAt ?? .distantPast) > ($1.closedAt ?? .distantPast) }
    }

    func restore(repository: String) {
        guard !repository.isEmpty else {
            loadTask?.cancel()
            issues = []
            self.repository = nil
            loadedRepository = nil
            hasSnapshot = false
            error = nil
            return
        }
        guard loadedRepository != repository else { return }
        loadTask?.cancel()
        loadTask = nil
        loadedRepository = repository
        self.repository = repository
        issues = snapshots[repository]?.issues ?? []
        hasSnapshot = snapshots[repository] != nil
        error = nil
    }

    func revalidate(repository: String, minimumAge: TimeInterval = 0) async {
        restore(repository: repository)
        guard !repository.isEmpty, loadedRepository == repository else { return }
        if minimumAge > 0,
           let fetchedAt = snapshots[repository]?.fetchedAt,
           Date().timeIntervalSince(fetchedAt) < minimumAge {
            return
        }
        if let loadTask { await loadTask.value; return }

        loading = true
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            // The flat list carries every issue, open and closed; the crews
            // come from a second call, since only open issues are flown.
            async let listData = GH.query([
                "issue", "list",
                "--repo", repository,
                "--assignee", "@me",
                "--state", "all",
                "--limit", "1000",
                "--json", "number,title,state,closedAt,createdAt,updatedAt,url,body",
            ], cacheFor: 30)
            async let crewData = GH.query([
                "api", "graphql",
                "-f", "query=\(Self.crewQuery)",
                "-f", "q=repo:\(repository) assignee:@me is:issue is:open",
            ], cacheFor: 30)
            // A closed issue has a parent too, and the closed lane lists
            // flights, not crews. Without this pass every landed crew looked
            // like a flight of its own down there.
            async let landedData = GH.query([
                "api", "graphql",
                "-f", "query=\(Self.parentQuery)",
                "-f", "q=repo:\(repository) assignee:@me is:issue is:closed sort:updated-desc",
            ], cacheFor: 30)
            let (data, crews, landed) = await (listData, crewData, landedData)
            guard !Task.isCancelled, loadedRepository == repository else { return }
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            guard let data else {
                if !hasSnapshot { error = GitHubFeed.ghHint }
                loading = false
                return
            }
            guard let fetched = try? decoder.decode([AssignedIssue].self, from: data) else {
                error = "Runway could not read the issues returned by GitHub."
                loading = false
                return
            }
            issues = Self.withCrews(fetched, from: crews, repository: repository)
            issues = Self.withParents(issues, from: landed)
            hasSnapshot = true
            error = nil
            snapshots[repository] = Snapshot(issues: issues, fetchedAt: Date())
            Self.write(snapshots)
            loading = false
        }
        loadTask = task
        await task.value
        loadTask = nil
    }

    /// Open or close an issue, then read the board back so the panes follow.
    func setClosed(_ closed: Bool, issue number: Int) async {
        guard let repository = loadedRepository else { return }
        _ = await GH.query([
            "issue", closed ? "close" : "reopen", String(number),
            "--repo", repository,
        ], cacheFor: 0)
        snapshots[repository] = nil
        await revalidate(repository: repository)
    }

    // MARK: Crews

    /// Sub-issues, and the flight each issue belongs to, for the open issues.
    /// Who each closed issue belongs to, and nothing else.
    private static let parentQuery = """
    query($q: String!) {
      search(query: $q, type: ISSUE, first: 100) {
        nodes { ... on Issue { number parent { number } } }
      }
    }
    """

    private static let crewQuery = """
    query($q: String!) {
      search(query: $q, type: ISSUE, first: 100) {
        nodes {
          ... on Issue {
            number
            parent { number }
            subIssues(first: 100) {
              nodes { number title state url repository { nameWithOwner } }
            }
          }
        }
      }
    }
    """

    /// Marks a landed crew as somebody's crew, so the closed lane can leave
    /// it out the same way the open one does.
    static func withParents(_ issues: [AssignedIssue], from data: Data?) -> [AssignedIssue] {
        guard let data,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let payload = json["data"] as? [String: Any],
              let search = payload["search"] as? [String: Any],
              let nodes = search["nodes"] as? [[String: Any]]
        else { return issues }
        var parents: [Int: Int] = [:]
        for node in nodes {
            guard let number = node["number"] as? Int,
                  let parent = node["parent"] as? [String: Any],
                  let owner = parent["number"] as? Int else { continue }
            parents[number] = owner
        }
        guard !parents.isEmpty else { return issues }
        return issues.map { issue in
            guard issue.parent == nil, let owner = parents[issue.number] else { return issue }
            var carried = issue
            carried.parent = owner
            return carried
        }
    }

    /// Hangs the crews off the issues they belong to. A leg in another
    /// repository keeps that repository's name; one at home does not.
    static func withCrews(
        _ issues: [AssignedIssue],
        from crewData: Data?,
        repository: String
    ) -> [AssignedIssue] {
        guard let crewData,
              let json = try? JSONSerialization.jsonObject(with: crewData) as? [String: Any],
              let data = json["data"] as? [String: Any],
              let search = data["search"] as? [String: Any],
              let nodes = search["nodes"] as? [[String: Any]] else { return issues }

        var legsByIssue: [Int: [IssueLeg]] = [:]
        var parentByIssue: [Int: Int] = [:]
        for node in nodes {
            guard let number = node["number"] as? Int else { continue }
            if let parent = node["parent"] as? [String: Any],
               let parentNumber = parent["number"] as? Int {
                parentByIssue[number] = parentNumber
            }
            let subNodes = (node["subIssues"] as? [String: Any])?["nodes"] as? [[String: Any]] ?? []
            let legs = subNodes.compactMap { sub -> IssueLeg? in
                guard let legNumber = sub["number"] as? Int,
                      let title = sub["title"] as? String,
                      let state = sub["state"] as? String,
                      let link = sub["url"] as? String,
                      let url = URL(string: link) else { return nil }
                let home = (sub["repository"] as? [String: Any])?["nameWithOwner"] as? String
                return IssueLeg(
                    number: legNumber,
                    title: title,
                    state: state,
                    url: url,
                    repository: home == repository ? nil : home
                )
            }
            if !legs.isEmpty { legsByIssue[number] = legs }
        }

        return issues.map { issue in
            var issue = issue
            issue.legs = legsByIssue[issue.number] ?? []
            issue.parent = parentByIssue[issue.number]
            return issue
        }
    }

    // MARK: Cache

    private static var cacheFile: URL {
        RunwayStorage.supportDir.appendingPathComponent("assigned-issues-cache.json")
    }

    private static func readSnapshots() -> [String: Snapshot] {
        guard let data = try? Data(contentsOf: cacheFile) else { return [:] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([String: Snapshot].self, from: data)) ?? [:]
    }

    private static func write(_ snapshots: [String: Snapshot]) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(snapshots) else { return }
        try? data.write(to: cacheFile)
    }
}
