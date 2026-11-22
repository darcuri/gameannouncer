import Foundation

/// A player's injury designation, from MFL's `injuries` export or ESPN's game summary.
public struct InjuryReport: Sendable, Equatable {
    /// As the source words it: "Questionable", "Out", "IR", "Suspended".
    public var status: String
    /// "Hamstring", when known.
    public var details: String?
    public var updated: Date?

    public init(status: String, details: String? = nil, updated: Date? = nil) {
        self.status = status
        self.details = details
        self.updated = updated
    }

    /// The short tag shown next to a name: "Q", "D", "O", "IR", "SUS".
    public var code: String {
        let s = status.lowercased()
        if s.hasPrefix("ir") || s.contains("injured reserve") { return "IR" }
        if s.hasPrefix("questionable") { return "Q" }
        if s.hasPrefix("doubtful") { return "D" }
        if s.hasPrefix("out") || s.hasPrefix("inactive") { return "O" }
        if s.hasPrefix("probable") { return "P" }
        if s.hasPrefix("susp") { return "SUS" }
        if s.hasPrefix("day") { return "DTD" }
        if s.hasPrefix("holdout") { return "HO" }
        if s.hasPrefix("retired") { return "RET" }
        return String(status.prefix(3)).uppercased()
    }

    /// "Questionable (Hamstring)"
    public var summary: String { details.map { "\(status) (\($0))" } ?? status }
}

/// MFL `injuries` export, by MFL player ID.
public struct MFLInjuries: Decodable, Sendable {
    public let reports: [String: InjuryReport]

    private struct Wire: Decodable {
        struct Root: Decodable { let timestamp: String?; let injury: OneOrMany<Row>? }
        struct Row: Decodable { let id: String; let status: String?; let details: String? }
        let injuries: Root
    }

    public init(from decoder: Decoder) throws {
        let root = try Wire(from: decoder).injuries
        let updated = root.timestamp.flatMap(TimeInterval.init).map(Date.init(timeIntervalSince1970:))
        var result: [String: InjuryReport] = [:]
        for row in root.injury?.values ?? [] {
            guard let status = row.status, !status.isEmpty else { continue }
            result[row.id] = InjuryReport(status: status, details: row.details.flatMap { $0.isEmpty ? nil : $0 },
                                          updated: updated)
        }
        reports = result
    }
}

/// What the display needs to know about one player's health.
public struct PlayerStatus: Sendable, Equatable {
    public var report: InjuryReport?
    /// The designation changed after kickoff, or the player was hurt on a play and hasn't
    /// returned.
    public var changedInGame = false
    /// "Injured during a play (Q2 4:12)", from the play-by-play.
    public var note: String?

    public var isEmpty: Bool { report == nil && note == nil && !changedInGame }
}

/// Tracks injury designations and notices when one changes during a player's game.
///
/// Three signals, none of which trusts timestamps (ESPN re-dates old entries mid-game):
/// - MFL's designation differs from the previous fetch, and the player's game has kicked off.
/// - ESPN's game summary lists a different designation than the last time we fetched that
///   game. Summaries are only fetched while a game is live, so any difference is in-game.
/// - The play-by-play says "BUF-J.Cook was injured during the play", with no later
///   "** Injury Update: BUF-J.Cook has returned to the game."
///
/// A designation that goes away is never flagged: getting healthier isn't news.
public struct InjuryTracker: Sendable {
    private struct PlayNote: Sendable {
        var injuredAt: String
        var update: String?
        var returned: Bool { update?.contains("returned") ?? false }
    }

    private var mfl: [String: InjuryReport]?
    private var mflChanged: Set<String> = []
    private var espn: [String: InjuryReport] = [:]
    private var espnChanged: Set<String> = []
    private var espnAthletes: [String: Set<String>] = [:]   // game ID → athlete IDs last listed
    private var notes: [String: [String: PlayNote]] = [:]   // game ID → "BUF j.cook" → note

    public init() {}

    /// `started` says whether a player's NFL game has kicked off this week.
    public mutating func ingest(mfl reports: [String: InjuryReport], started: (String) -> Bool) {
        defer { mfl = reports }
        guard let previous = mfl else { return }
        for (id, report) in reports {
            if !started(id) {
                mflChanged.remove(id)
            } else if previous[id]?.status != report.status {
                mflChanged.insert(id)
            }
        }
    }

    /// One live game's injury list, by ESPN athlete ID.
    public mutating func ingest(espn reports: [String: InjuryReport], gameID: String) {
        if let listed = espnAthletes[gameID] {
            for (id, report) in reports where espn[id]?.status != report.status {
                espnChanged.insert(id)
            }
            for id in listed.subtracting(reports.keys) { espn[id] = nil }
        }
        espnAthletes[gameID] = Set(reports.keys)
        espn.merge(reports) { _, new in new }
    }

    /// One game's whole play-by-play, in order.
    public mutating func ingest(plays: [Play], gameID: String) {
        var found: [String: PlayNote] = [:]
        for play in plays where play.text.contains("njur") {
            let when = "\(play.period > 4 ? "OT" : "Q\(play.period)") \(play.clock)".trimmingCharacters(in: .whitespaces)
            for match in play.text.matches(of: Self.injuredPattern) {
                guard let team = match.output[1].substring, let name = match.output[2].substring else { continue }
                found[Self.key(name, team: Self.team(team))] = PlayNote(injuredAt: when)
            }
            for match in play.text.matches(of: Self.updatePattern) {
                guard let team = match.output[1].substring, let name = match.output[2].substring,
                      let update = match.output[3].substring else { continue }
                found[Self.key(name, team: Self.team(team)), default: PlayNote(injuredAt: when)].update = String(update)
            }
        }
        notes[gameID] = found
    }

    /// `gameID` is the player's game this week, for matching play-by-play mentions.
    public func status(for player: FantasyPlayer, gameID: String?) -> PlayerStatus {
        var status = PlayerStatus()
        let espnReport = player.espnID.flatMap { espn[$0] }
        let espnMoved = player.espnID.map(espnChanged.contains) ?? false
        // ESPN's in-game list is fresher than MFL's export once it has moved.
        status.report = espnMoved ? espnReport ?? mfl?[player.id] : mfl?[player.id] ?? espnReport
        status.changedInGame = status.report != nil && (espnMoved || mflChanged.contains(player.id))

        if !player.isTeamDefense, let gameID, let short = player.abbreviatedName,
           let note = notes[gameID]?[Self.key(Substring(short), team: player.team)] {
            if note.returned {
                status.note = "Injured during a play (\(note.injuredAt)), then returned to the game"
            } else {
                status.note = "Injured during a play (\(note.injuredAt))" + (note.update.map { ": \($0)" } ?? "")
                status.changedInGame = true
            }
        }
        return status
    }

    /// ESPN drops suffixes ("M.Penix" for "Penix Jr., Michael").
    /// The team is part of the key: "BLT-L.Jackson" is Lamar Jackson, not Buffalo's Landon.
    private static func key(_ name: Substring, team: NFLTeam) -> String {
        "\(team.code) " + PlayerNames.withoutSuffix(name.lowercased().trimmingCharacters(in: .whitespaces))
    }

    /// Play-by-play text uses the NFL's own abbreviations, which differ from ESPN's and MFL's
    /// for a few teams.
    private static func team(_ prefix: Substring) -> NFLTeam {
        let nfl = ["ARZ": "ARI", "BLT": "BAL", "CLV": "CLE", "HST": "HOU", "LA": "LAR"]
        return nfl[String(prefix)].map(NFLTeam.init(mfl:)) ?? NFLTeam(espn: String(prefix))
    }

    // "ARZ-J.Love was injured during the play." The name can't run through another "XX-"
    // prefix, or earlier text in the same play ("GB-J.Love pass incomplete. GB-J.Love was
    // injured...") would be swallowed into it.
    nonisolated(unsafe) private static let injuredPattern =
        try! Regex(#"([A-Z]{2,4})-([A-Z](?:(?![A-Z]{2,4}-)[\w.' -])*?) was injured during the play"#)
    // "** Injury Update: DAL-J.Ferguson has returned to the game."
    nonisolated(unsafe) private static let updatePattern =
        try! Regex(#"Injury Update: ([A-Z]{2,4})-([A-Z][\w.' -]*?) ((?:has|is|will|was) [^.*]*)"#)
}

/// One item from ESPN's per-player news feed.
public struct PlayerNewsItem: Sendable, Equatable, Identifiable {
    public var id: String
    public var headline: String
    /// Plain text; Rotowire's analysis paragraph, or a story's teaser.
    public var body: String?
    public var published: Date?
    public var link: URL?
    /// "Rotowire", "Story", "Media"
    public var source: String

    public init(id: String, headline: String, body: String? = nil, published: Date? = nil,
                link: URL? = nil, source: String = "") {
        self.id = id
        self.headline = headline
        self.body = body
        self.published = published
        self.link = link
        self.source = source
    }
}

public struct PlayerNews: Decodable, Sendable {
    public let items: [PlayerNewsItem]

    private struct Wire: Decodable {
        struct Item: Decodable {
            struct Links: Decodable {
                struct Web: Decodable { let href: String? }
                let web: Web?
            }
            let id: Int?
            let type: String?
            let headline: String?
            let description: String?
            let story: String?
            let published: String?
            let links: Links?
        }
        let feed: [Item]?
    }

    public init(from decoder: Decoder) throws {
        items = (try Wire(from: decoder).feed ?? []).enumerated().compactMap { index, item in
            guard let headline = item.headline, !headline.isEmpty else { return nil }
            let rotowire = item.type == "Rotowire"
            // Rotowire's story is a plain paragraph; other stories are full HTML articles,
            // so show their teaser and link out.
            let body = rotowire ? item.story : item.description
            return PlayerNewsItem(
                id: item.id.map(String.init) ?? "item-\(index)",
                headline: headline,
                body: body.flatMap { $0.isEmpty || $0 == headline ? nil : $0 },
                published: item.published.flatMap { try? Date($0, strategy: .iso8601) },
                link: item.links?.web?.href.flatMap(URL.init(string:)),
                source: item.type ?? "")
        }
        .sorted { ($0.published ?? .distantPast) > ($1.published ?? .distantPast) }
    }
}
