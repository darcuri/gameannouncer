import Foundation

/// ESPN's undocumented site API. Used only for play-level detail (scorer names, sacks),
/// which MFL doesn't provide. Treat it as best-effort: it can change without notice.
public struct ESPNClient: Sendable {
    private static let base = URL(string: "https://site.api.espn.com/apis/site/v2/sports/football/nfl")!
    private let http: HTTP

    public init(userAgent: String) { http = HTTP(userAgent: userAgent) }

    public func scoreboard() async throws -> Data {
        try await http.get(Self.base.appending(path: "scoreboard"))
    }

    public func summary(eventID: String) async throws -> Data {
        try await http.get(Self.base.appending(path: "summary").appending(queryItems: [.init(name: "event", value: eventID)]))
    }
}

/// Just enough of the scoreboard to know which events exist and their state.
public struct ESPNScoreboard: Decodable, Sendable {
    public struct Event: Decodable, Sendable {
        public struct Status: Decodable, Sendable {
            public struct Kind: Decodable, Sendable { public let state: String } // pre / in / post
            public let type: Kind
        }
        public let id: String
        public let shortName: String
        public let status: Status

        public var isLive: Bool { status.type.state == "in" }
        public var isFinal: Bool { status.type.state == "post" }
    }
    public let events: [Event]
}
