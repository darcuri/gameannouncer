import Foundation
import GameAnnouncerCore

/// A fictional league on a busy Sunday afternoon, for screenshots and trying the app
/// without an MFL league: `GameAnnouncer -demo YES`. Fantasy teams and players are made
/// up; the NFL teams are real because the NFL Games tab is built around them.
@MainActor
enum DemoData {
    static let myFranchise = "0001"

    /// Sunday 3:12 PM, so the early games are late and the afternoon games are on.
    static let now: Date = {
        let today = Calendar.current.startOfDay(for: .now)
        return Calendar.current.date(bySettingHour: 15, minute: 12, second: 4, of: today) ?? .now
    }()

    private static func at(_ hour: Int, _ minute: Int) -> Date {
        Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: now) ?? now
    }

    // MARK: League

    static let league = FantasyLeague(name: "Sunday Showdown League", franchises: [
        .init(id: "0001", name: "Gridiron Gurus"),
        .init(id: "0002", name: "Blitz Brigade"),
        .init(id: "0003", name: "End Zone Express"),
        .init(id: "0004", name: "Fourth & Long"),
        .init(id: "0005", name: "Hail Mary Heroes"),
        .init(id: "0006", name: "Pigskin Pirates"),
        .init(id: "0007", name: "Red Zone Rebels"),
        .init(id: "0008", name: "The Audibles"),
        .init(id: "0009", name: "Two-Minute Drill"),
        .init(id: "0010", name: "Pick Six Posse"),
        .init(id: "0011", name: "Sack Masters"),
        .init(id: "0012", name: "Hang Time"),
    ])

    // MARK: Players

    private static func player(_ id: String, _ name: String, _ position: String, _ team: String) -> FantasyPlayer {
        FantasyPlayer(id: id, name: name, position: position, team: NFLTeam(mfl: team))
    }

    static let players = PlayerDatabase(players: [
        // Gridiron Gurus
        player("D01", "Brooks, Tyler", "QB", "BUF"),
        player("D02", "Hale, Marcus", "RB", "PHI"),
        player("D03", "Rivers, Dante", "RB", "KCC"),
        player("D04", "Pierce, Jalen", "WR", "SFO"),
        player("D05", "Whitaker, Cole", "WR", "DET"),
        player("D06", "Lyons, Andre", "WR", "LAR"),
        player("D07", "Kessler, Noah", "TE", "CIN"),
        player("D08", "Ortiz, Sam", "PK", "BUF"),
        player("D09", "Seahawks, Seattle", "Def", "SEA"),
        player("D10", "Marsh, Evan", "QB", "NYJ"),
        player("D11", "Grant, Isaiah", "RB", "HOU"),
        player("D12", "Barrett, Leo", "WR", "CHI"),
        player("D13", "Callahan, Reid", "TE", "MIN"),
        // Blitz Brigade
        player("D21", "Dunn, Caleb", "QB", "MIA"),
        player("D22", "Vance, Jordan", "RB", "DAL"),
        player("D23", "Foster, Malik", "RB", "SEA"),
        player("D24", "Sutton, Trey", "WR", "DEN"),
        player("D25", "Cole, Darius", "WR", "GBP"),
        player("D26", "Ellis, Rashad", "WR", "ARI"),
        player("D27", "Pratt, Owen", "TE", "BAL"),
        player("D28", "Navarro, Luis", "PK", "DAL"),
        player("D29", "Chiefs, Kansas City", "Def", "KCC"),
        player("D30", "Holt, Gavin", "QB", "JAC"),
        player("D31", "Mercer, Ty", "RB", "NEP"),
        player("D32", "Quinn, Elias", "WR", "MIN"),
        // Unrostered, but named in plays
        player("D40", "Grady, Thomas", "QB", "SFO"),
        player("D41", "Monroe, Kendrick", "CB", "SEA"),
        player("D42", "Okafor, Victor", "DE", "BUF"),
        player("D43", "Reyes, Mateo", "QB", "PHI"),
        player("D44", "Lindqvist, Erik", "LB", "DAL"),
    ])

    // MARK: Fantasy scoring

    private static func score(_ id: String, _ points: Double, starter: Bool = true, remaining: Int) -> LiveScoring.PlayerScore {
        LiveScoring.PlayerScore(id: id, score: points, isStarter: starter, gameSecondsRemaining: remaining)
    }

    private static func team(_ id: String, _ points: Double, home: Bool, yet: Int, playing: Int,
                             _ players: [LiveScoring.PlayerScore] = []) -> LiveScoring.Franchise {
        LiveScoring.Franchise(id: id, score: points, isHome: home, playersYetToPlay: yet,
                              playersCurrentlyPlaying: playing, players: players)
    }

    static let liveScoring = LiveScoring(matchups: [
        LiveScoring.Matchup(franchises: [
            team("0002", 96.60, home: false, yet: 1, playing: 5, [
                score("D21", 15.60, remaining: 1200), score("D22", 19.70, remaining: 2400),
                score("D23", 22.10, remaining: 600), score("D24", 12.40, remaining: 0),
                score("D25", 8.60, remaining: 1800), score("D26", 4.20, remaining: 3000),
                score("D27", 0, remaining: 3600), score("D28", 5.00, remaining: 2400),
                score("D29", 9.00, remaining: 0),
                score("D30", 0, starter: false, remaining: 3600), score("D31", 13.80, starter: false, remaining: 0),
                score("D32", 0, starter: false, remaining: 3600),
            ]),
            team("0001", 96.70, home: true, yet: 1, playing: 6, [
                score("D01", 21.40, remaining: 1200), score("D02", 14.20, remaining: 2400),
                score("D03", 18.90, remaining: 0), score("D04", 16.30, remaining: 600),
                score("D05", 9.80, remaining: 1800), score("D06", 3.10, remaining: 3000),
                score("D07", 0, remaining: 3600), score("D08", 7.00, remaining: 1200),
                score("D09", 6.00, remaining: 600),
                score("D10", 11.20, starter: false, remaining: 0), score("D11", 0, starter: false, remaining: 3600),
                score("D12", 0, starter: false, remaining: 3600), score("D13", 0, starter: false, remaining: 3600),
            ]),
        ]),
        LiveScoring.Matchup(franchises: [team("0003", 88.45, home: false, yet: 2, playing: 3),
                                         team("0004", 102.30, home: true, yet: 0, playing: 4)]),
        LiveScoring.Matchup(franchises: [team("0005", 71.20, home: false, yet: 3, playing: 2),
                                         team("0006", 64.85, home: true, yet: 2, playing: 4)]),
        LiveScoring.Matchup(franchises: [team("0007", 110.15, home: false, yet: 0, playing: 2),
                                         team("0008", 79.40, home: true, yet: 1, playing: 5)]),
        LiveScoring.Matchup(franchises: [team("0009", 58.90, home: false, yet: 4, playing: 3),
                                         team("0010", 83.75, home: true, yet: 2, playing: 2)]),
        LiveScoring.Matchup(franchises: [team("0011", 92.05, home: false, yet: 1, playing: 4),
                                         team("0012", 90.60, home: true, yet: 1, playing: 3)]),
    ])

    // MARK: NFL games

    private static func side(_ id: String, _ code: String, _ location: String, _ nickname: String, _ score: Int) -> GameState.Side {
        GameState.Side(espnID: id, team: NFLTeam(mfl: code), location: location, nickname: nickname, score: score)
    }

    static let buffaloMiami = GameState(
        id: "G1", away: side("2", "BUF", "Buffalo", "Bills", 17), home: side("15", "MIA", "Miami", "Dolphins", 10),
        phase: .live, period: 3, clock: "4:12", possessionESPNID: "2", inRedZone: true)
    static let philadelphiaDallas = GameState(
        id: "G2", away: side("21", "PHI", "Philadelphia", "Eagles", 14), home: side("6", "DAL", "Dallas", "Cowboys", 17),
        phase: .live, period: 2, clock: "1:48", possessionESPNID: "6", inRedZone: false)
    static let kansasCityDenver = GameState(
        id: "G3", away: side("12", "KCC", "Kansas City", "Chiefs", 27), home: side("7", "DEN", "Denver", "Broncos", 20),
        phase: .final, period: 4, clock: "0:00", possessionESPNID: nil, inRedZone: false)
    static let sanFranciscoSeattle = GameState(
        id: "G4", away: side("25", "SFO", "San Francisco", "49ers", 21), home: side("26", "SEA", "Seattle", "Seahawks", 31),
        phase: .live, period: 4, clock: "8:31", possessionESPNID: "25", inRedZone: false)
    static let detroitGreenBay = GameState(
        id: "G5", away: side("8", "DET", "Detroit", "Lions", 13), home: side("9", "GBP", "Green Bay", "Packers", 10),
        phase: .halftime, period: 2, clock: "0:00", possessionESPNID: nil, inRedZone: false)
    static let ramsArizona = GameState(
        id: "G6", away: side("14", "LAR", "Los Angeles", "Rams", 3), home: side("22", "ARI", "Arizona", "Cardinals", 0),
        phase: .live, period: 1, clock: "9:02", possessionESPNID: "22", inRedZone: true)
    static let jetsNewEngland = GameState(
        id: "G7", away: side("20", "NYJ", "New York", "Jets", 16), home: side("17", "NEP", "New England", "Patriots", 19),
        phase: .final, period: 4, clock: "0:00", possessionESPNID: nil, inRedZone: false)

    static let games: [GameState] = [
        kansasCityDenver, jetsNewEngland, buffaloMiami, philadelphiaDallas, sanFranciscoSeattle, detroitGreenBay, ramsArizona,
        GameState(id: "G8", away: side("34", "HOU", "Houston", "Texans", 0), home: side("30", "JAC", "Jacksonville", "Jaguars", 0),
                  phase: .scheduled, period: 0, clock: "", possessionESPNID: nil, inRedZone: false, kickoff: at(16, 5)),
        GameState(id: "G9", away: side("4", "CIN", "Cincinnati", "Bengals", 0), home: side("33", "BAL", "Baltimore", "Ravens", 0),
                  phase: .scheduled, period: 0, clock: "", possessionESPNID: nil, inRedZone: false, kickoff: at(16, 25)),
        GameState(id: "G10", away: side("3", "CHI", "Chicago", "Bears", 0), home: side("16", "MIN", "Minnesota", "Vikings", 0),
                  phase: .scheduled, period: 0, clock: "", possessionESPNID: nil, inRedZone: false, kickoff: at(20, 20)),
    ]

    // MARK: Play log (oldest first)

    private static func event(_ kind: GameEvent.Kind, _ game: GameState, team: GameState.Side?, offense: String? = nil,
                              text: String = "", away: Int, home: Int, at time: Date) -> GameEvent {
        let play = text.isEmpty ? nil : Play(id: UUID().uuidString, sequence: 0, kind: .other, text: text,
                                             awayScore: away, homeScore: home, offenseTeamID: offense)
        return GameEvent(kind: kind, game: game, team: team, play: play, awayScore: away, homeScore: home, observedAt: time)
    }

    static var events: [GameEvent] {
        let bufMia = buffaloMiami, phiDal = philadelphiaDallas, kcDen = kansasCityDenver
        let sfSea = sanFranciscoSeattle, detGb = detroitGreenBay, larAri = ramsArizona
        return [
            event(.touchdown, kcDen, team: kcDen.away, offense: "12", text: "Dante Rivers 4 Yd Rush (Harrison Butler Kick)",
                  away: 24, home: 20, at: at(14, 41)),
            event(.final, jetsNewEngland, team: nil, away: 16, home: 19, at: at(14, 52)),
            event(.final, kcDen, team: nil, away: 27, home: 20, at: at(14, 58)),
            event(.sack, bufMia, team: bufMia.away, offense: "15", text: "(Shotgun) C.Dunn sacked at MIA 30 for -7 yards (V.Okafor).",
                  away: 10, home: 10, at: at(15, 1)),
            event(.interception, sfSea, team: sfSea.home, offense: "25",
                  text: "(Shotgun) T.Grady pass short middle intended for J.Pierce INTERCEPTED by K.Monroe at SEA 22.",
                  away: 21, home: 24, at: at(15, 3)),
            event(.touchdown, sfSea, team: sfSea.home, offense: "25", text: "Kendrick Monroe 38 Yd Interception Return (Jason Kerr Kick)",
                  away: 21, home: 31, at: at(15, 4)),
            event(.fieldGoal, phiDal, team: phiDal.home, offense: "6", text: "Luis Navarro 44 Yd Field Goal",
                  away: 14, home: 17, at: at(15, 6)),
            event(.halftime, detGb, team: nil, away: 13, home: 10, at: at(15, 7)),
            event(.redZone, bufMia, team: bufMia.away, away: 17, home: 10, at: at(15, 8)),
            event(.touchdown, bufMia, team: bufMia.away, offense: "2", text: "Tyler Brooks 3 Yd Rush (Sam Ortiz Kick)",
                  away: 17, home: 10, at: at(15, 9)),
            event(.fumbleLost, phiDal, team: phiDal.home, offense: "21",
                  text: "M.Reyes pass short right to M.Hale to DAL 41 for 6 yards (E.Lindqvist). FUMBLES (E.Lindqvist), RECOVERED by DAL-E.Lindqvist at DAL 40.",
                  away: 14, home: 17, at: at(15, 10)),
            event(.redZone, larAri, team: larAri.home, away: 3, home: 0, at: at(15, 11)),
        ]
    }
}
