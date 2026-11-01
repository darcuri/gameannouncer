import Foundation

/// Talks to MyFantasyLeague. Requests are serialized and spaced out, per MFL's guidance
/// (~1 s between calls, never retry a 429 immediately).
public actor MFLClient {
    public static let apiHost = URL(string: "https://api.myfantasyleague.com")!

    public let year: Int
    public let leagueID: String?
    private let apiKey: String?
    private let http: HTTP
    private let minSpacing: Duration
    private var leagueHost: URL?
    private var lastRequest: ContinuousClock.Instant?
    private var backoffUntil: ContinuousClock.Instant?

    public init(
        year: Int,
        leagueID: String?,
        apiKey: String? = nil,
        userAgent: String,
        minSpacing: Duration = .milliseconds(1100)
    ) {
        self.year = year
        self.leagueID = leagueID
        self.apiKey = apiKey
        self.http = HTTP(userAgent: userAgent)
        self.minSpacing = minSpacing
    }

    // MARK: Site-wide (api host)

    public func status() async throws -> MFLStatus {
        let data = try await throttled { try await self.http.get(self.dynamicURL("mfl_status.json")) }
        return try JSONDecoder().decode(MFLStatusResponse.self, from: data).mfl_status
    }

    /// Live NFL game state. Unlike `TYPE=nflSchedule`, this static file updates during games.
    public func nflSchedule(week: Int, etag: String?) async throws -> ConditionalResponse {
        try await throttled { try await self.http.get(self.dynamicURL("nfl_sched_\(week).json"), etag: etag) }
    }

    /// Full player database. Changes about once a day; cache it.
    public func players() async throws -> Data {
        try await export(type: "players", params: ["DETAILS": "1"], host: Self.apiHost, league: false)
    }

    // MARK: League-scoped

    public func league() async throws -> Data {
        let data = try await export(type: "league", params: [:])
        if let base = try? JSONDecoder().decode(LeagueBaseURL.self, from: data).league.baseURL,
           let url = URL(string: base) {
            leagueHost = url
        }
        return data
    }

    public func liveScoring(week: Int) async throws -> Data {
        try await export(type: "liveScoring", params: ["W": String(week), "DETAILS": "1"])
    }

    public func projectedScores(week: Int) async throws -> Data {
        try await export(type: "projectedScores", params: ["W": String(week)])
    }

    // MARK: Plumbing

    private func dynamicURL(_ file: String) -> URL {
        Self.apiHost.appending(path: "fflnetdynamic\(year)/\(file)")
    }

    private func export(
        type: String, params: [String: String], host: URL? = nil, league: Bool = true
    ) async throws -> Data {
        var items = [URLQueryItem(name: "TYPE", value: type), URLQueryItem(name: "JSON", value: "1")]
        if league {
            guard let leagueID else { preconditionFailure("league export without a league ID") }
            items.append(URLQueryItem(name: "L", value: leagueID))
            if let apiKey { items.append(URLQueryItem(name: "APIKEY", value: apiKey)) }
        }
        items += params.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        let base = host ?? leagueHost ?? Self.apiHost
        let url = base.appending(path: "\(year)/export").appending(queryItems: items)
        return try await throttled { try await self.http.get(url) }
    }

    private func throttled<T: Sendable>(_ body: @Sendable () async throws -> T) async throws -> T {
        let clock = ContinuousClock()
        if let backoffUntil, clock.now < backoffUntil {
            try await clock.sleep(until: backoffUntil)
        }
        if let lastRequest {
            let next = lastRequest + minSpacing
            if clock.now < next { try await clock.sleep(until: next) }
        }
        lastRequest = clock.now
        do {
            return try await body()
        } catch FetchError.rateLimited {
            backoffUntil = clock.now + .seconds(60)
            throw FetchError.rateLimited
        }
    }
}

public struct MFLStatus: Decodable, Sendable {
    public struct Weeks: Decodable, Sendable {
        public let CurrentWeek: String
        public let LiveScoringWeek: String
        public let UpcomingWeek: String
    }
    public let year: String
    public let weeks: Weeks

    public var liveScoringWeek: Int? { Int(weeks.LiveScoringWeek) }
}

private struct MFLStatusResponse: Decodable { let mfl_status: MFLStatus }
private struct LeagueBaseURL: Decodable {
    struct League: Decodable { let baseURL: String? }
    let league: League
}
