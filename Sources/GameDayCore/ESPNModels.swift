import Foundation

// Wire models for ESPN's site API. Only the fields we use are decoded; everything is
// optional where ESPN has been seen to omit it. Convert to domain types (GameState, Play)
// right away rather than passing these around.

public struct ESPNScoreboard: Decodable, Sendable {
    public let events: [ESPNEvent]

    public var games: [GameState] { events.compactMap(\.gameState) }
}

public struct ESPNEvent: Decodable, Sendable {
    public let id: String
    public let shortName: String
    public let status: ESPNStatus
    public let competitions: [ESPNCompetition]

    public var isLive: Bool { status.type.state == "in" }
    public var isFinal: Bool { status.type.state == "post" }
}

public struct ESPNStatus: Decodable, Sendable {
    public struct Kind: Decodable, Sendable {
        public let name: String   // STATUS_SCHEDULED, STATUS_IN_PROGRESS, STATUS_HALFTIME, STATUS_FINAL, ...
        public let state: String  // pre / in / post
    }
    public let period: Int?
    public let displayClock: String?
    public let type: Kind
}

public struct ESPNCompetition: Decodable, Sendable {
    public struct Competitor: Decodable, Sendable {
        public struct Team: Decodable, Sendable {
            public let id: String
            public let abbreviation: String
            public let location: String?
            public let name: String?
        }
        public let id: String
        public let homeAway: String
        public let score: String?
        public let team: Team
    }
    public struct Situation: Decodable, Sendable {
        public let possession: String?
        public let isRedZone: Bool?
        public let downDistanceText: String?
    }
    public let competitors: [Competitor]
    public let situation: Situation?
}

public struct ESPNSummary: Decodable, Sendable {
    public struct Header: Decodable, Sendable {
        public let id: String
        public let competitions: [ESPNCompetition]
    }
    public struct Drives: Decodable, Sendable {
        public struct Drive: Decodable, Sendable { public let plays: [ESPNPlay]? }
        public let previous: [Drive]?
        public let current: Drive?
    }
    public struct ScoringPlay: Decodable, Sendable {
        public let id: String
        public let text: String
    }

    public let header: Header
    public let drives: Drives?
    public let scoringPlays: [ScoringPlay]?

    public var eventID: String { header.id }

    /// Every play in game order, with scoring plays carrying ESPN's clean summary text
    /// ("Ja'Marr Chase 30 Yd pass from Joe Burrow (Evan McPherson Kick)") instead of the raw
    /// play-by-play text.
    public var plays: [Play] {
        let clean = Dictionary((scoringPlays ?? []).map { ($0.id, $0.text) }, uniquingKeysWith: { a, _ in a })
        let raw = (drives?.previous ?? []).flatMap { $0.plays ?? [] } + (drives?.current?.plays ?? [])
        var seen = Set<String>()
        return raw
            .filter { seen.insert($0.id).inserted } // the current drive can repeat the last previous one
            .sorted { $0.sequence < $1.sequence }
            .map { $0.play(summaryText: clean[$0.id]) }
    }
}

public struct ESPNPlay: Decodable, Sendable {
    public struct Kind: Decodable, Sendable { public let id: String?; public let text: String }
    public struct Period: Decodable, Sendable { public let number: Int }
    public struct Clock: Decodable, Sendable { public let displayValue: String? }
    public struct Spot: Decodable, Sendable {
        public struct Team: Decodable, Sendable { public let id: String? }
        public let team: Team?
    }

    public let id: String
    public let sequenceNumber: String?
    public let type: Kind?
    public let text: String?
    public let awayScore: Int?
    public let homeScore: Int?
    public let period: Period?
    public let clock: Clock?
    public let scoringPlay: Bool?
    public let isTurnover: Bool?
    public let wallclock: String?
    public let start: Spot?

    var sequence: Int { Int(sequenceNumber ?? "") ?? Int(id.suffix(6)) ?? 0 }

    func play(summaryText: String?) -> Play {
        Play(
            id: id,
            sequence: sequence,
            kind: PlayKind(espnType: type?.text ?? "", isScoring: scoringPlay ?? false),
            text: summaryText ?? text ?? "",
            awayScore: awayScore ?? 0,
            homeScore: homeScore ?? 0,
            period: period?.number ?? 0,
            clock: clock?.displayValue ?? "",
            offenseTeamID: start?.team?.id,
            isTurnover: isTurnover ?? false,
            wallclock: wallclock.flatMap { try? Date($0, strategy: .iso8601) }
        )
    }
}

extension ESPNEvent {
    var gameState: GameState? {
        guard let competition = competitions.first,
              let away = competition.competitors.first(where: { $0.homeAway == "away" }),
              let home = competition.competitors.first(where: { $0.homeAway == "home" })
        else { return nil }

        func side(_ c: ESPNCompetition.Competitor) -> GameState.Side {
            GameState.Side(
                espnID: c.team.id,
                team: NFLTeam(espn: c.team.abbreviation),
                location: c.team.location ?? c.team.abbreviation,
                nickname: c.team.name ?? c.team.abbreviation,
                score: Int(c.score ?? "") ?? 0
            )
        }

        let phase: GameState.Phase = switch status.type.state {
        case "in": status.type.name == "STATUS_HALFTIME" ? .halftime : .live
        case "post": .final
        default: .scheduled
        }

        let situation = competition.situation
        return GameState(
            id: id,
            away: side(away),
            home: side(home),
            phase: phase,
            period: status.period ?? 0,
            clock: status.displayClock ?? "",
            possessionESPNID: situation?.possession,
            inRedZone: situation?.isRedZone ?? false
        )
    }
}
