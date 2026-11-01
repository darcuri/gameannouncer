import Foundation
import Testing
@testable import GameDayCore

private let t0 = Date(timeIntervalSince1970: 1_793_556_000)

private func game(
    phase: GameState.Phase = .live, away: Int = 0, home: Int = 0,
    possession: String? = nil, redZone: Bool = false
) -> GameState {
    GameState(
        id: "G1",
        away: .init(espnID: "33", team: NFLTeam(mfl: "BAL"), location: "Baltimore", nickname: "Ravens", score: away),
        home: .init(espnID: "2", team: NFLTeam(mfl: "BUF"), location: "Buffalo", nickname: "Bills", score: home),
        phase: phase, period: 1, clock: "10:00",
        possessionESPNID: possession, inRedZone: redZone
    )
}

private func play(
    _ id: String, _ kind: PlayKind, away: Int = 0, home: Int = 0,
    offense: String = "2", text: String = "", at: Date = t0
) -> Play {
    Play(id: id, sequence: Int(id)!, kind: kind, text: text, awayScore: away, homeScore: home,
         offenseTeamID: offense, wallclock: at)
}

@Test func firstScoreboardOnlySeeds() {
    var differ = EventDiffer()
    #expect(differ.ingest(scoreboard: [game(away: 7, possession: "2", redZone: true)], at: t0).isEmpty)
}

@Test func phaseTransitions() {
    var differ = EventDiffer()
    _ = differ.ingest(scoreboard: [game(phase: .scheduled)], at: t0)
    #expect(differ.ingest(scoreboard: [game(phase: .live)], at: t0).map(\.kind) == [.kickoff])
    #expect(differ.ingest(scoreboard: [game(phase: .halftime)], at: t0).map(\.kind) == [.halftime])
    _ = differ.ingest(scoreboard: [game(phase: .live)], at: t0)
    #expect(differ.ingest(scoreboard: [game(phase: .final)], at: t0).map(\.kind) == [.final])
}

@Test func redZoneAnnouncedOncePerPossession() throws {
    var differ = EventDiffer()
    _ = differ.ingest(scoreboard: [game(possession: "2")], at: t0)
    let entered = differ.ingest(scoreboard: [game(possession: "2", redZone: true)], at: t0)
    #expect(entered.map(\.kind) == [.redZone])
    #expect(try #require(entered.first?.team).location == "Buffalo")
    #expect(differ.ingest(scoreboard: [game(possession: "2", redZone: true)], at: t0).isEmpty)
    // Turnover inside the 20, the other team now has it in the red zone.
    #expect(differ.ingest(scoreboard: [game(possession: "33", redZone: true)], at: t0).map(\.kind) == [.redZone])
}

@Test func scoreDropIsCorrection() {
    var differ = EventDiffer()
    _ = differ.ingest(scoreboard: [game(home: 7)], at: t0)
    #expect(differ.ingest(scoreboard: [game(home: 0)], at: t0).map(\.kind) == [.scoreCorrection])
}

@Test func newPlaysAnnouncedOnce() {
    var differ = EventDiffer()
    _ = differ.ingest(scoreboard: [game()], at: t0)
    let plays = [play("1", .other), play("2", .touchdown, home: 7)]
    #expect(differ.ingest(plays: plays, gameID: "G1", at: t0).map(\.kind) == [.touchdown])
    #expect(differ.ingest(plays: plays, gameID: "G1", at: t0 + 30).isEmpty)
}

@Test func scoringTeamComesFromScoreDelta() throws {
    var differ = EventDiffer()
    _ = differ.ingest(scoreboard: [game()], at: t0)
    // Buffalo has the ball (offense 2) but Baltimore returns an interception for a TD.
    let plays = [play("1", .other, home: 7), play("2", .touchdown, away: 7, home: 7, offense: "2")]
    let event = try #require(differ.ingest(plays: plays, gameID: "G1", at: t0).first)
    #expect(event.team?.location == "Baltimore")
    #expect(event.awayScore == 7 && event.homeScore == 7)
}

@Test func defenseGetsCreditForSack() throws {
    var differ = EventDiffer()
    _ = differ.ingest(scoreboard: [game()], at: t0)
    let event = try #require(differ.ingest(plays: [play("1", .sack, offense: "33")], gameID: "G1", at: t0).first)
    #expect(event.kind == .sack)
    #expect(event.team?.location == "Buffalo")
}

@Test func stalePlaysAreSilent() {
    var differ = EventDiffer(maxPlayAge: 300)
    _ = differ.ingest(scoreboard: [game()], at: t0)
    let old = play("1", .touchdown, home: 7, at: t0)
    let fresh = play("2", .fieldGoal, home: 10, at: t0 + 590)
    let events = differ.ingest(plays: [old, fresh], gameID: "G1", at: t0 + 600)
    #expect(events.map(\.kind) == [.fieldGoal])
}

@Test func playThatBecomesScoringAfterReviewIsAnnounced() {
    var differ = EventDiffer()
    _ = differ.ingest(scoreboard: [game()], at: t0)
    _ = differ.ingest(plays: [play("1", .other)], gameID: "G1", at: t0)
    let reviewed = differ.ingest(plays: [play("1", .touchdown, home: 6)], gameID: "G1", at: t0 + 60)
    #expect(reviewed.map(\.kind) == [.touchdown])
}

@Test func playsBeforeScoreboardAreRememberedNotAnnounced() {
    var differ = EventDiffer()
    #expect(differ.ingest(plays: [play("1", .touchdown, home: 7)], gameID: "G1", at: t0).isEmpty)
    _ = differ.ingest(scoreboard: [game(home: 7)], at: t0)
    #expect(differ.ingest(plays: [play("1", .touchdown, home: 7)], gameID: "G1", at: t0).isEmpty)
}

// MARK: Announcements and fantasy relevance

private let chase = FantasyPlayer(id: "1", name: "Allen, Josh", position: "QB", team: NFLTeam(mfl: "BUF"))
private let bills = FantasyPlayer(id: "2", name: "Bills, Buffalo", position: "Def", team: NFLTeam(mfl: "BUF"))
private let henry = FantasyPlayer(id: "3", name: "Henry, Derrick", position: "RB", team: NFLTeam(mfl: "BAL"))

@Test func touchdownAnnouncementReadsNaturally() throws {
    var differ = EventDiffer()
    _ = differ.ingest(scoreboard: [game()], at: t0)
    let td = play("1", .touchdown, home: 7, text: "Josh Allen 5 Yd Rush (Tyler Bass Kick)")
    let event = try #require(differ.ingest(plays: [td], gameID: "G1", at: t0).first)
    // Involving one of my players makes it relevant, but the announcement is just the play and score.
    let context = FantasyContext(myStarters: [chase], opponentStarters: [henry])
    #expect(context.involvement(in: event).map(\.player) == [chase])
    #expect(Announcement.text(for: event) == "Touchdown, Buffalo Bills! Josh Allen 5 yard run. Buffalo Bills lead 7 to 0.")
}

@Test func touchdownBeforeTryOmitsScoreThenReportsMiss() throws {
    var differ = EventDiffer()
    _ = differ.ingest(scoreboard: [game()], at: t0)
    let td = play("1", .touchdown, home: 6, text: "Josh Allen 5 Yd Rush ")
    let announced = try #require(differ.ingest(plays: [td], gameID: "G1", at: t0).first)
    #expect(announced.tryPending)
    #expect(Announcement.text(for: announced) == "Touchdown, Buffalo Bills! Josh Allen 5 yard run.")
    // Still the last play: nothing to conclude yet.
    #expect(differ.ingest(plays: [td], gameID: "G1", at: t0 + 30).isEmpty)
    // Kickoff follows with the score unchanged: the try failed.
    let kickoff = play("2", .other, home: 6, offense: "33")
    let followUp = differ.ingest(plays: [td, kickoff], gameID: "G1", at: t0 + 60)
    #expect(followUp.map(\.kind) == [.tryFailed])
    #expect(Announcement.text(for: followUp[0]) == "Buffalo Bills misses the try after the touchdown. Buffalo Bills lead 6 to 0.")
}

@Test func madeKickAfterPendingTouchdownIsSilent() {
    var differ = EventDiffer()
    _ = differ.ingest(scoreboard: [game()], at: t0)
    _ = differ.ingest(plays: [play("1", .touchdown, home: 6)], gameID: "G1", at: t0)
    let later = [play("1", .touchdown, home: 7), play("2", .other, home: 7, offense: "33")]
    #expect(differ.ingest(plays: later, gameID: "G1", at: t0 + 60).isEmpty)
}

@Test func twoPointConversionIsAnnounced() {
    var differ = EventDiffer()
    _ = differ.ingest(scoreboard: [game()], at: t0)
    _ = differ.ingest(plays: [play("1", .touchdown, home: 6)], gameID: "G1", at: t0)
    let later = [play("1", .touchdown, home: 8), play("2", .other, home: 8, offense: "33")]
    #expect(differ.ingest(plays: later, gameID: "G1", at: t0 + 60).map(\.kind) == [.twoPointGood])
}

@Test func missingPossessionDoesNotRetriggerRedZone() {
    var differ = EventDiffer()
    _ = differ.ingest(scoreboard: [game(possession: "2", redZone: true)], at: t0)
    // After a field goal ESPN drops possession, then restores it with a stale red-zone flag.
    #expect(differ.ingest(scoreboard: [game(home: 3, possession: nil, redZone: true)], at: t0).isEmpty)
    #expect(differ.ingest(scoreboard: [game(home: 3, possession: "2", redZone: true)], at: t0).isEmpty)
}

@Test func teamsUseFullNames() {
    let jets = GameState.Side(espnID: "20", team: NFLTeam(mfl: "NYJ"), location: "New York", nickname: "Jets", score: 0)
    #expect(Announcement.fullName(jets) == "New York Jets")
}

@Test func redZoneAndGameStatusUseFullNames() throws {
    var differ = EventDiffer()
    _ = differ.ingest(scoreboard: [game(phase: .scheduled, possession: "2")], at: t0)
    let kickoff = try #require(differ.ingest(scoreboard: [game(possession: "2")], at: t0).first)
    #expect(Announcement.text(for: kickoff) == "Kickoff: Baltimore Ravens at Buffalo Bills.")
    let redZone = try #require(differ.ingest(scoreboard: [game(possession: "2", redZone: true)], at: t0).first)
    #expect(Announcement.text(for: redZone) == "Buffalo Bills in the red zone against the Baltimore Ravens.")
}

@Test func failedExtraPointIsMentioned() throws {
    var differ = EventDiffer()
    _ = differ.ingest(scoreboard: [game()], at: t0)
    let td = play("1", .touchdown, away: 6, offense: "33", text: "Derrick Henry 12 Yd Rush (Justin Tucker PAT failed)")
    let event = try #require(differ.ingest(plays: [td], gameID: "G1", at: t0).first)
    let context = FantasyContext(myStarters: [chase], opponentStarters: [henry])
    // Opponent involvement makes the play relevant but isn't spoken.
    #expect(context.isRelevant(event, scope: .myPlayers))
    #expect(Announcement.text(for: event)
        == "Touchdown, Baltimore Ravens! Derrick Henry 12 yard run. Extra point no good. Baltimore Ravens lead 6 to 0.")
}

@Test func teamDefenseNotCreditedForOffensiveTouchdown() throws {
    var differ = EventDiffer()
    _ = differ.ingest(scoreboard: [game()], at: t0)
    let context = FantasyContext(myStarters: [bills], opponentStarters: [])
    // Buffalo on offense scores: not a defensive play.
    let offensive = try #require(differ.ingest(plays: [play("1", .touchdown, home: 7, offense: "2")], gameID: "G1", at: t0).first)
    #expect(context.involvement(in: offensive).isEmpty)
    // Baltimore on offense, Buffalo scores: pick-six or fumble return.
    let pickSix = try #require(differ.ingest(plays: [play("1", .touchdown, home: 7, offense: "2"),
                                                     play("2", .touchdown, home: 14, offense: "33")],
                                             gameID: "G1", at: t0).first)
    #expect(context.involvement(in: pickSix).map(\.player) == [bills])
}

@Test func teamDefenseInvolvedInItsSack() throws {
    var differ = EventDiffer()
    _ = differ.ingest(scoreboard: [game()], at: t0)
    let event = try #require(differ.ingest(plays: [play("1", .sack, offense: "33")], gameID: "G1", at: t0).first)
    let context = FantasyContext(myStarters: [bills], opponentStarters: [])
    #expect(context.involvement(in: event).map(\.player) == [bills])
    #expect(context.isRelevant(event, scope: .myPlayers))
}

@Test func scopeFiltersGames() throws {
    var differ = EventDiffer()
    _ = differ.ingest(scoreboard: [game(phase: .scheduled)], at: t0)
    let kickoff = try #require(differ.ingest(scoreboard: [game()], at: t0).first)
    let elsewhere = FantasyContext(
        myStarters: [FantasyPlayer(id: "9", name: "Kelce, Travis", position: "TE", team: NFLTeam(mfl: "KCC"))],
        opponentStarters: []
    )
    #expect(elsewhere.isRelevant(kickoff, scope: .all))
    #expect(!elsewhere.isRelevant(kickoff, scope: .myGames))
    #expect(FantasyContext(myStarters: [], opponentStarters: [henry]).isRelevant(kickoff, scope: .myGames))
}

// MARK: Defensive, special-teams and turnover formats

private let names = PlayerNames(PlayerDatabase(players: [
    FantasyPlayer(id: "10", name: "Fagnano, Joe", position: "QB", team: NFLTeam(mfl: "BAL")),
    FantasyPlayer(id: "11", name: "Parker, T.J.", position: "DE", team: NFLTeam(mfl: "BUF")),
    FantasyPlayer(id: "12", name: "Rousseau, Gregory", position: "DE", team: NFLTeam(mfl: "BUF")),
    FantasyPlayer(id: "13", name: "Allen, Josh", position: "QB", team: NFLTeam(mfl: "BUF")),
    FantasyPlayer(id: "14", name: "Washington, Broderick", position: "DT", team: NFLTeam(mfl: "BAL")),
    FantasyPlayer(id: "15", name: "Moore, D.J.", position: "WR", team: NFLTeam(mfl: "BUF")),
    FantasyPlayer(id: "16", name: "Tampa, T.J.", position: "CB", team: NFLTeam(mfl: "BAL")),
    FantasyPlayer(id: "17", name: "Huntley, Tyler", position: "QB", team: NFLTeam(mfl: "BAL")),
    FantasyPlayer(id: "18", name: "Penix Jr., Michael", position: "QB", team: NFLTeam(mfl: "BAL")),
]))

private func announce(_ kind: PlayKind, home: Int = 0, offense: String, _ text: String) throws -> String {
    var differ = EventDiffer()
    _ = differ.ingest(scoreboard: [game()], at: t0)
    let event = try #require(differ.ingest(plays: [play("1", kind, home: home, offense: offense, text: text)],
                                           gameID: "G1", at: t0).first)
    return Announcement.text(for: event, names: names)
}

@Test func sackFormat() throws {
    #expect(try announce(.sack, offense: "33", "(Shotgun) J.Fagnano sacked at BLT 28 for -2 yards (T.Parker).")
        == "Sack, Buffalo Bills, Joe Fagnano sacked by T.J. Parker for 2 yards.")
    #expect(try announce(.sack, offense: "33", "J.Fagnano sacked at BLT 45 for -5 yards (sack split by T.Parker and G.Rousseau).")
        == "Sack, Buffalo Bills, Joe Fagnano sacked by T.J. Parker and Gregory Rousseau for 5 yards.")
    #expect(try announce(.sack, offense: "33", "M.Penix sacked at ATL 30 for no gain (T.Parker).")
        == "Sack, Buffalo Bills, Michael Penix Jr. sacked by T.J. Parker for no gain.")
    #expect(try announce(.interception, offense: "33", "M.Penix pass deep left intended for X.Y INTERCEPTED by T.Parker at BUF 9.")
        == "Interception, Buffalo Bills, T.J. Parker picks off Michael Penix Jr.")
}

@Test func interceptionFormat() throws {
    #expect(try announce(.interception, offense: "2",
                         "J.Allen pass short middle intended for J.Hawes INTERCEPTED by B.Washington at BUF 17. B.Washington to BUF 17 for no gain.")
        == "Interception, Baltimore Ravens, Broderick Washington picks off Josh Allen.")
}

@Test func fumbleFormatUsesFinalCallAfterReview() throws {
    let text = "(Shotgun) J.Allen pass short middle to D.Moore to BLT 20 for 19 yards (M.Starks).The Replay Official reviewed the runner was down by contact ruling, and the play was REVERSED.(Shotgun) J.Allen pass short middle to D.Moore to BLT 21 for 18 yards (R.Smith). FUMBLES (R.Smith), RECOVERED by BLT-T.Tampa at BLT 18."
    #expect(try announce(.fumbleLost, offense: "2", text)
        == "Fumble, D.J. Moore fumbles and is recovered by Baltimore Ravens T.J. Tampa.")
}

@Test func stripSackIsAFumble() throws {
    #expect(PlayKind(espnType: "Sack Opp Fumble Recovery", isScoring: false) == .fumbleLost)
    let text = "(Shotgun) T.Huntley sacked at BLT 31 for -9 yards (C.Bishop). FUMBLES (C.Bishop), touched at BLT 22, RECOVERED by BUF-T.Parker at BLT 20."
    #expect(try announce(.fumbleLost, offense: "33", text)
        == "Fumble, Tyler Huntley fumbles and is recovered by Buffalo Bills T.J. Parker.")
}

@Test func defensiveTouchdownFormat() throws {
    #expect(try announce(.touchdown, home: 7, offense: "33", "Rayuan Lane III 92 Yd Interception Return (Tyler Bass Kick)")
        == "Touchdown, Buffalo Bills Defense, Rayuan Lane III, 92 yard interception. Buffalo Bills lead 7 to 0.")
    #expect(try announce(.touchdown, home: 7, offense: "33", "Terrel Bernard 23 Yd Fumble Return (Tyler Bass Kick)")
        == "Touchdown, Buffalo Bills Defense, Terrel Bernard, 23 yard fumble recovery. Buffalo Bills lead 7 to 0.")
}

@Test func returnTouchdownFormat() throws {
    #expect(try announce(.touchdown, home: 7, offense: "33", "Dylan Laube 95 Yd Kickoff Return (Matt Gay Kick)")
        == "Touchdown, Buffalo Bills, Dylan Laube, 95 yard kickoff return. Buffalo Bills lead 7 to 0.")
    #expect(try announce(.touchdown, home: 7, offense: "33", "Khalil Shakir 80 Yd Punt Return (Tyler Bass Kick)")
        == "Touchdown, Buffalo Bills, Khalil Shakir, 80 yard punt return. Buffalo Bills lead 7 to 0.")
}

@Test func offenseRecoveringOwnFumbleForTouchdownIsNotDefense() throws {
    #expect(try announce(.touchdown, home: 7, offense: "2",
                         "Javonte Williams 2 Yd Rush Javonte Williams Fumble James Mitchell 0 Yd Fumble Recovery (Brandon Aubrey Kick)")
        == "Touchdown, Buffalo Bills, James Mitchell, fumble recovery in the end zone. Buffalo Bills lead 7 to 0.")
}

@Test func extraPointTryIsNotARedZoneEntry() {
    var differ = EventDiffer()
    // Buffalo in the red zone, scores; then the try (no down) shows them "in the red zone" again.
    _ = differ.ingest(scoreboard: [game(possession: "2", redZone: true)], at: t0)
    _ = differ.ingest(scoreboard: [game(home: 6, possession: nil, redZone: false)], at: t0)
    var tryAttempt = game(home: 6, possession: "2", redZone: true)
    tryAttempt.isLiveDown = false
    #expect(differ.ingest(scoreboard: [tryAttempt], at: t0).isEmpty)
    // Kickoff to Baltimore, then Baltimore's first real down at its own 25.
    var kickoff = game(home: 7, possession: "33", redZone: false)
    kickoff.isLiveDown = false
    #expect(differ.ingest(scoreboard: [kickoff], at: t0).isEmpty)
    #expect(differ.ingest(scoreboard: [game(home: 7, possession: "33", redZone: false)], at: t0).isEmpty)
    // A real Baltimore drive into the red zone is still announced.
    #expect(differ.ingest(scoreboard: [game(home: 7, possession: "33", redZone: true)], at: t0).map(\.kind) == [.redZone])
}
