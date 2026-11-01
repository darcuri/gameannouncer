import Foundation

/// A player from MFL's player database.
public struct FantasyPlayer: Sendable, Equatable, Hashable {
    public var id: String
    public var name: String       // MFL style: "Chase, Ja'Marr"; defenses are "Bills, Buffalo"
    public var position: String
    public var team: NFLTeam

    public init(id: String, name: String, position: String, team: NFLTeam) {
        self.id = id
        self.name = name
        self.position = position
        self.team = team
    }

    public var isTeamDefense: Bool { position == "Def" || position == "ST" || position == "Off" }

    /// "Ja'Marr Chase"
    public var displayName: String {
        let parts = name.split(separator: ",", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
        return parts.count == 2 ? "\(parts[1]) \(parts[0])" : name
    }

    /// "J.Chase", the form ESPN's raw play-by-play uses.
    var abbreviatedName: String? {
        let parts = name.split(separator: ",", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count == 2, let initial = parts[1].first else { return nil }
        return "\(initial).\(parts[0])"
    }
}

public struct PlayerDatabase: Decodable, Sendable {
    public let players: [String: FantasyPlayer]

    private struct Wire: Decodable {
        struct Players: Decodable { let player: OneOrMany<Row> }
        struct Row: Decodable { let id: String; let name: String; let position: String; let team: String }
        let players: Players
    }

    public init(players: [FantasyPlayer]) {
        self.players = Dictionary(players.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
    }

    public init(from decoder: Decoder) throws {
        let rows = try Wire(from: decoder).players.player.values
        self.init(players: rows.map { FantasyPlayer(id: $0.id, name: $0.name, position: $0.position, team: NFLTeam(mfl: $0.team)) })
    }
}

/// Expands ESPN's play-by-play abbreviations ("T.Parker") to full names ("T.J. Parker")
/// using MFL's player database, which includes defensive players.
public struct PlayerNames: Sendable {
    private let byLastName: [String: [FantasyPlayer]]

    private static let teamEntries: Set<String> = ["Def", "ST", "Off", "Coach", "XX"]

    public init(_ database: PlayerDatabase) {
        let individuals = database.players.values.filter {
            !Self.teamEntries.contains($0.position) && !$0.position.hasPrefix("TM")
        }
        // ESPN drops suffixes ("M.Penix" for "Penix Jr., Michael"), so index both forms.
        var index: [String: [FantasyPlayer]] = [:]
        for player in individuals {
            let last = Self.lastName(of: player).lowercased()
            index[last, default: []].append(player)
            let bare = Self.withoutSuffix(last)
            if bare != last { index[bare, default: []].append(player) }
        }
        byLastName = index
    }

    private static func withoutSuffix(_ name: String) -> String {
        for suffix in [" jr.", " jr", " sr.", " sr", " ii", " iii", " iv", " v"] where name.hasSuffix(suffix) {
            return String(name.dropLast(suffix.count))
        }
        return name
    }

    /// "T.Parker" on BUF → "T.J. Parker". Falls back to "T. Parker" when there's no single match.
    public func fullName(_ abbreviated: String, team: NFLTeam?) -> String {
        guard let dot = abbreviated.firstIndex(of: ".") else { return abbreviated }
        let initials = abbreviated[..<dot].lowercased()
        let last = abbreviated[abbreviated.index(after: dot)...].trimmingCharacters(in: .whitespaces)
        let fallback = "\(abbreviated[..<dot]). \(last)"
        let candidates = (byLastName[last.lowercased()] ?? []).filter {
            (team == nil || $0.team == team) && Self.firstName(of: $0).lowercased().hasPrefix(initials)
        }
        return candidates.count == 1 ? candidates[0].displayName : fallback
    }

    private static func lastName(of p: FantasyPlayer) -> String {
        String(p.name.split(separator: ",", maxSplits: 1).first ?? "").trimmingCharacters(in: .whitespaces)
    }

    private static func firstName(of p: FantasyPlayer) -> String {
        let parts = p.name.split(separator: ",", maxSplits: 1)
        return parts.count == 2 ? parts[1].trimmingCharacters(in: .whitespaces) : ""
    }
}

/// MFL `liveScoring` export.
public struct LiveScoring: Decodable, Sendable {
    public struct Matchup: Sendable {
        public let franchises: [Franchise]
        public init(franchises: [Franchise]) { self.franchises = franchises }
    }
    public struct Franchise: Sendable {
        public let id: String
        public let score: Double
        public let isHome: Bool
        public let playersYetToPlay: Int
        public let playersCurrentlyPlaying: Int
        public let players: [PlayerScore]
        public var starters: [PlayerScore] { players.filter { $0.isStarter } }
        public var bench: [PlayerScore] { players.filter { !$0.isStarter } }

        public init(id: String, score: Double, isHome: Bool, playersYetToPlay: Int,
                    playersCurrentlyPlaying: Int, players: [PlayerScore]) {
            self.id = id
            self.score = score
            self.isHome = isHome
            self.playersYetToPlay = playersYetToPlay
            self.playersCurrentlyPlaying = playersCurrentlyPlaying
            self.players = players
        }
    }
    public struct PlayerScore: Sendable {
        public let id: String
        public let score: Double
        public let isStarter: Bool
        /// 3600 before kickoff, 0 when the game is over (or a bye).
        public let gameSecondsRemaining: Int

        public init(id: String, score: Double, isStarter: Bool, gameSecondsRemaining: Int) {
            self.id = id
            self.score = score
            self.isStarter = isStarter
            self.gameSecondsRemaining = gameSecondsRemaining
        }
    }

    public let matchups: [Matchup]

    public init(matchups: [Matchup]) { self.matchups = matchups }

    /// Matchups this franchise plays in. Some leagues schedule more than one per week.
    public func matchups(for franchiseID: String) -> [Matchup] {
        matchups.filter { $0.franchises.contains { $0.id == franchiseID } }
    }

    private struct Wire: Decodable {
        struct Root: Decodable { let matchup: OneOrMany<M> }
        struct M: Decodable { let franchise: OneOrMany<F> }
        struct F: Decodable {
            struct Players: Decodable { let player: OneOrMany<P> }
            let id: String
            let score: String?
            let isHome: String?
            let playersYetToPlay: String?
            let playersCurrentlyPlaying: String?
            let players: Players?
        }
        struct P: Decodable { let id: String; let score: String?; let status: String?; let gameSecondsRemaining: String? }
        let liveScoring: Root
    }

    public init(from decoder: Decoder) throws {
        matchups = try Wire(from: decoder).liveScoring.matchup.values.map { m in
            Matchup(franchises: m.franchise.values.map { f in
                Franchise(
                    id: f.id,
                    score: Double(f.score ?? "") ?? 0,
                    isHome: f.isHome == "1",
                    playersYetToPlay: Int(f.playersYetToPlay ?? "") ?? 0,
                    playersCurrentlyPlaying: Int(f.playersCurrentlyPlaying ?? "") ?? 0,
                    players: (f.players?.player.values ?? []).map {
                        PlayerScore(id: $0.id, score: Double($0.score ?? "") ?? 0, isStarter: $0.status == "starter",
                                    gameSecondsRemaining: Int($0.gameSecondsRemaining ?? "") ?? 0)
                    }
                )
            })
        }
    }
}

/// MFL `league` export: just what the display needs.
public struct FantasyLeague: Decodable, Sendable {
    public struct Franchise: Sendable, Identifiable {
        public let id: String
        public let name: String
        public init(id: String, name: String) { self.id = id; self.name = name }
    }

    public let name: String
    public let franchises: [Franchise]

    public init(name: String, franchises: [Franchise]) {
        self.name = name
        self.franchises = franchises
    }

    public func franchiseName(_ id: String) -> String {
        franchises.first { $0.id == id }?.name ?? "Team \(id)"
    }

    private struct Wire: Decodable {
        struct League: Decodable {
            struct Franchises: Decodable { let franchise: OneOrMany<F> }
            struct F: Decodable { let id: String; let name: String }
            let name: String
            let franchises: Franchises
        }
        let league: League
    }

    public init(from decoder: Decoder) throws {
        let league = try Wire(from: decoder).league
        name = league.name
        franchises = league.franchises.franchise.values.map { Franchise(id: $0.id, name: $0.name) }
    }
}

/// Which events matter to one franchise, and which of its (or its opponents') players were
/// involved.
public struct FantasyContext: Sendable {
    public enum Scope: String, Sendable, CaseIterable {
        case all       // every NFL game
        case myGames   // games with any of my or my opponents' starters
        case myPlayers // only plays that involve my or my opponents' starters
    }

    public struct Involvement: Sendable, Equatable {
        public var player: FantasyPlayer
        public var isMine: Bool
    }

    public let myStarters: [FantasyPlayer]
    public let opponentStarters: [FantasyPlayer]

    public init(myStarters: [FantasyPlayer], opponentStarters: [FantasyPlayer]) {
        self.myStarters = myStarters
        self.opponentStarters = opponentStarters
    }

    public init(franchiseID: String, liveScoring: LiveScoring, players: PlayerDatabase) {
        let matchups = liveScoring.matchups(for: franchiseID)
        let franchises = matchups.flatMap(\.franchises)
        func starters(_ f: LiveScoring.Franchise) -> [FantasyPlayer] { f.starters.compactMap { players.players[$0.id] } }
        myStarters = franchises.first { $0.id == franchiseID }.map(starters) ?? []
        let mine = Set(myStarters)
        // A player can face me twice in a doubleheader week; list them once.
        opponentStarters = Array(Set(franchises.filter { $0.id != franchiseID }.flatMap(starters)).subtracting(mine))
            .sorted { $0.id < $1.id }
    }

    public func involvement(in event: GameEvent) -> [Involvement] {
        guard let play = event.play else { return [] }
        let teams = Set(event.game.teams)
        func involved(_ p: FantasyPlayer) -> Bool {
            guard teams.contains(p.team) else { return false }
            if p.isTeamDefense {
                guard let team = event.team, team.team == p.team else { return false }
                switch event.kind {
                case .sack, .interception, .fumbleLost, .safety:
                    return true
                case .touchdown:
                    // Only defensive and return touchdowns, where the scorer wasn't on offense.
                    return play.offenseTeamID != nil && play.offenseTeamID != team.espnID
                default:
                    return false
                }
            }
            if play.text.contains(p.displayName) { return true }
            if let short = p.abbreviatedName, play.text.contains(short) { return true }
            return false
        }
        return myStarters.filter(involved).map { Involvement(player: $0, isMine: true) }
            + opponentStarters.filter(involved).map { Involvement(player: $0, isMine: false) }
    }

    public func isRelevant(_ event: GameEvent, scope: Scope) -> Bool {
        switch scope {
        case .all:
            return true
        case .myGames:
            let teams = Set((myStarters + opponentStarters).map(\.team))
            return event.game.teams.contains(where: teams.contains)
        case .myPlayers:
            return !involvement(in: event).isEmpty
        }
    }
}
