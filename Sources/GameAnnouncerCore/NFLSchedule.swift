import Foundation

/// Decoded form of `fflnetdynamic{YEAR}/nfl_sched_{W}.json`.
public struct NFLSchedule: Decodable, Sendable {
    public let week: String
    public let lastUpdate: String?
    public let games: [NFLGame]

    private enum Keys: String, CodingKey { case nflSchedule }
    private enum Inner: String, CodingKey { case week, lastUpdate, matchup }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self).nestedContainer(keyedBy: Inner.self, forKey: .nflSchedule)
        week = try c.decode(String.self, forKey: .week)
        lastUpdate = try c.decodeIfPresent(String.self, forKey: .lastUpdate)
        games = try c.decode(OneOrMany<NFLGame>.self, forKey: .matchup).values
    }
}

public struct NFLGame: Decodable, Sendable {
    public enum Status: String, Sendable {
        case scheduled = "SCHED"
        case inProgress = "INPROG"
        case final = "FINAL"
        case unknown
    }

    public struct Team: Decodable, Sendable {
        public let id: String
        @LenientInt public var score: Int?
        public let hasPossession: String?
        public let inRedZone: String?
        public let isHome: String?
    }

    public let kickoff: Date
    public let rawStatus: String
    @LenientInt public var gameSecondsRemaining: Int?
    public let team: [Team]

    public var status: Status { Status(rawValue: rawStatus) ?? .unknown }

    private enum CodingKeys: String, CodingKey { case kickoff, status, gameSecondsRemaining, team }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let ts = try c.decode(String.self, forKey: .kickoff)
        kickoff = Date(timeIntervalSince1970: TimeInterval(ts) ?? 0)
        rawStatus = try c.decode(String.self, forKey: .status)
        _gameSecondsRemaining = try c.decode(LenientInt.self, forKey: .gameSecondsRemaining)
        team = try c.decode(OneOrMany<Team>.self, forKey: .team).values
    }
}

extension NFLSchedule {
    /// Any game not yet final whose kickoff has passed counts as live. MFL may lag in
    /// flipping SCHED→INPROG, so kickoff time is used as a backstop.
    public func liveGames(at now: Date = .now) -> [NFLGame] {
        games.filter { $0.status == .inProgress || ($0.status == .scheduled && $0.kickoff <= now) }
    }

    public func nextKickoff(after now: Date = .now) -> Date? {
        games.filter { $0.status == .scheduled && $0.kickoff > now }.map(\.kickoff).min()
    }
}
