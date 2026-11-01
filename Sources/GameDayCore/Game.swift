import Foundation

/// NFL team identity, keyed by MFL's abbreviation, since that's what MFL's player DB uses
/// and ESPN's differ for a handful of teams.
public struct NFLTeam: Hashable, Sendable, CustomStringConvertible {
    public let code: String

    public init(mfl code: String) { self.code = code }

    public init(espn abbreviation: String) {
        code = Self.espnToMFL[abbreviation] ?? abbreviation
    }

    public var description: String { code }

    private static let espnToMFL = [
        "GB": "GBP", "KC": "KCC", "LV": "LVR", "NE": "NEP", "NO": "NOS",
        "SF": "SFO", "TB": "TBB", "JAX": "JAC", "WSH": "WAS",
    ]
}

/// A snapshot of one NFL game, from the scoreboard.
public struct GameState: Sendable, Equatable {
    public enum Phase: Sendable, Equatable { case scheduled, live, halftime, final }

    public struct Side: Sendable, Equatable {
        public var espnID: String
        public var team: NFLTeam
        public var location: String  // "Buffalo"
        public var nickname: String  // "Bills"
        public var score: Int
    }

    public var id: String
    public var away: Side
    public var home: Side
    public var phase: Phase
    public var period: Int
    public var clock: String
    public var possessionESPNID: String?
    public var inRedZone: Bool
    public var kickoff: Date? = nil

    public var teams: [NFLTeam] { [away.team, home.team] }

    /// "Q3 4:12", "Halftime", "Final", "OT 2:00", or the kickoff time before the game.
    public var statusText: String {
        switch phase {
        case .scheduled:
            return kickoff?.formatted(.dateTime.weekday(.abbreviated).hour().minute()) ?? "Scheduled"
        case .halftime:
            return "Halftime"
        case .final:
            return period > 4 ? "Final/OT" : "Final"
        case .live:
            return "\(period > 4 ? "OT" : "Q\(period)") \(clock)"
        }
    }

    public func side(for team: NFLTeam) -> Side? {
        away.team == team ? away : home.team == team ? home : nil
    }

    public var possessionTeam: NFLTeam? { side(espnID: possessionESPNID)?.team }

    public func side(espnID: String?) -> Side? {
        if away.espnID == espnID { return away }
        if home.espnID == espnID { return home }
        return nil
    }
}

public enum PlayKind: Sendable, Equatable {
    case touchdown, fieldGoal, safety, otherScore
    case sack, interception, fumbleLost
    case other

    init(espnType: String, isScoring: Bool) {
        let t = espnType.lowercased()
        if t.contains("touchdown") {
            self = .touchdown
        } else if t.contains("field goal good") {
            self = .fieldGoal
        } else if t.contains("safety") {
            self = .safety
        } else if isScoring {
            self = .otherScore
        } else if t == "sack" {
            self = .sack
        } else if t.contains("interception") {
            self = .interception
        } else if t.contains("fumble recovery (opponent)") || t == "sack opp fumble recovery" {
            self = .fumbleLost
        } else {
            self = .other
        }
    }

    public var isScoring: Bool { [.touchdown, .fieldGoal, .safety, .otherScore].contains(self) }
}

/// One play from a game's play-by-play.
public struct Play: Sendable, Equatable {
    public var id: String
    public var sequence: Int
    public var kind: PlayKind
    public var text: String
    public var awayScore: Int
    public var homeScore: Int
    public var period: Int
    public var clock: String
    public var offenseTeamID: String?
    public var isTurnover: Bool
    public var wallclock: Date?

    public init(
        id: String, sequence: Int, kind: PlayKind, text: String = "",
        awayScore: Int = 0, homeScore: Int = 0, period: Int = 1, clock: String = "",
        offenseTeamID: String? = nil, isTurnover: Bool = false, wallclock: Date? = nil
    ) {
        self.id = id
        self.sequence = sequence
        self.kind = kind
        self.text = text
        self.awayScore = awayScore
        self.homeScore = homeScore
        self.period = period
        self.clock = clock
        self.offenseTeamID = offenseTeamID
        self.isTurnover = isTurnover
        self.wallclock = wallclock
    }
}
