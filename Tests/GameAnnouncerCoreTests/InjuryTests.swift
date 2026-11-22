import Foundation
import Testing
@testable import GameAnnouncerCore

private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
    try JSONDecoder().decode(type, from: Data(json.utf8))
}

// MARK: - InjuryReport

@Test func injuryCodesMapStatuses() {
    let expected: [(String, String)] = [
        ("Questionable", "Q"), ("Doubtful", "D"), ("Out", "O"), ("Inactive", "O"),
        ("IR", "IR"), ("IR-R", "IR"), ("IR-PUP", "IR"), ("Injured Reserve", "IR"),
        ("Probable", "P"), ("Suspended", "SUS"), ("Suspension", "SUS"),
        ("Day-To-Day", "DTD"), ("Holdout", "HO"), ("Retired", "RET"), ("Weird", "WEI"),
    ]
    for (status, code) in expected {
        #expect(InjuryReport(status: status).code == code, "\(status)")
    }
}

@Test func injurySummaryIncludesDetails() {
    #expect(InjuryReport(status: "Questionable", details: "Hamstring").summary == "Questionable (Hamstring)")
    #expect(InjuryReport(status: "Out").summary == "Out")
}

// MARK: - MFLInjuries

@Test func mflInjuriesDecodeArray() throws {
    let json = """
    {"injuries":{"timestamp":"1795369465","week":"11","injury":[
      {"id":"11317","status":"Questionable","details":"Hamstring","exp_return":"Nov 29, 2026"},
      {"id":"12345","status":"Out","details":""}]}}
    """
    let injuries = try decode(MFLInjuries.self, json)
    #expect(injuries.reports.count == 2)
    #expect(injuries.reports["11317"]?.status == "Questionable")
    #expect(injuries.reports["11317"]?.details == "Hamstring")
    #expect(injuries.reports["11317"]?.updated == Date(timeIntervalSince1970: 1795369465))
    #expect(injuries.reports["12345"]?.details == nil)
}

@Test func mflInjuriesDecodeSingleObject() throws {
    let json = #"{"injuries":{"week":"11","injury":{"id":"1","status":"Doubtful","details":"Knee"}}}"#
    let injuries = try decode(MFLInjuries.self, json)
    #expect(injuries.reports["1"]?.code == "D")
}

@Test func mflInjuriesDecodeMissingList() throws {
    let injuries = try decode(MFLInjuries.self, #"{"injuries":{"timestamp":"1","week":"1"}}"#)
    #expect(injuries.reports.isEmpty)
}

// MARK: - PlayerDatabase

@Test func playerDatabasePicksUpJerseyAndESPNID() throws {
    let json = """
    {"players":{"player":[
      {"id":"1","name":"Love, Jordan","position":"QB","team":"GBP","jersey":"10","espn_id":"4036378"},
      {"id":"2","name":"Bills, Buffalo","position":"Def","team":"BUF"},
      {"id":"3","name":"Doe, John","position":"WR","team":"BUF","jersey":"","espn_id":""}]}}
    """
    let db = try decode(PlayerDatabase.self, json)
    #expect(db.players["1"]?.jersey == "10")
    #expect(db.players["1"]?.espnID == "4036378")
    #expect(db.players["2"]?.jersey == nil)
    #expect(db.players["2"]?.espnID == nil)
    #expect(db.players["3"]?.jersey == nil)
    #expect(db.players["3"]?.espnID == nil)
}

// MARK: - ESPNSummary injuries

@Test func espnSummaryInjuryReports() throws {
    let json = """
    {"header":{"id":"401","competitions":[]},
     "injuries":[
      {"injuries":[
        {"status":"Questionable","date":"2026-11-01T20:51Z","athlete":{"id":"4379399"},
         "details":{"type":"Hamstring","detail":"Not Specified"}},
        {"status":"Out","athlete":{"id":"111"},"details":{"type":"Knee","detail":"Sprain"}}]},
      {"injuries":[
        {"status":"Suspension","athlete":{"id":"222"}},
        {"status":"Out"}]}]}
    """
    let summary = try decode(ESPNSummary.self, json)
    let reports = summary.injuryReports
    #expect(reports.count == 3)
    #expect(reports["4379399"]?.status == "Questionable")
    #expect(reports["4379399"]?.details == "Hamstring")   // "Not Specified" dropped
    #expect(reports["4379399"]?.updated != nil)
    #expect(reports["111"]?.details == "Knee, Sprain")
    #expect(reports["222"]?.code == "SUS")
    #expect(reports["222"]?.details == nil)
}

@Test func espnSummaryWithoutInjuries() throws {
    let summary = try decode(ESPNSummary.self, #"{"header":{"id":"401","competitions":[]}}"#)
    #expect(summary.injuryReports.isEmpty)
}

// MARK: - PlayerNews

@Test func playerNewsDecodesSortsAndPicksBody() throws {
    let json = """
    {"feed":[
      {"id":1,"type":"Story","headline":"Older story","description":"Teaser","story":"<p>Full</p>",
       "published":"2026-11-01T10:00:00Z","links":{"web":{"href":"https://espn.com/a"}}},
      {"id":2,"type":"Rotowire","headline":"Newer note","description":"Short","story":"Analysis paragraph.",
       "published":"2026-11-02T10:00:00Z"},
      {"id":3,"type":"Media","description":"No headline","published":"2026-11-03T10:00:00Z"},
      {"id":4,"type":"Media","headline":"","published":"2026-11-04T10:00:00Z"}]}
    """
    let news = try decode(PlayerNews.self, json)
    #expect(news.items.map(\.id) == ["2", "1"])
    #expect(news.items[0].body == "Analysis paragraph.")
    #expect(news.items[0].source == "Rotowire")
    #expect(news.items[1].body == "Teaser")
    #expect(news.items[1].link == URL(string: "https://espn.com/a"))
    #expect(news.items[1].published != nil)
}

@Test func playerNewsEmptyFeed() throws {
    #expect(try decode(PlayerNews.self, "{}").items.isEmpty)
}

// MARK: - InjuryTracker

private let love = FantasyPlayer(id: "1", name: "Love, Jordan", position: "QB",
                                 team: NFLTeam(mfl: "GBP"), espnID: "100")
private let penix = FantasyPlayer(id: "2", name: "Penix Jr., Michael", position: "QB",
                                  team: NFLTeam(mfl: "ATL"), espnID: "200")
private let defense = FantasyPlayer(id: "3", name: "Packers, Green Bay", position: "Def",
                                    team: NFLTeam(mfl: "GBP"))

private func play(_ text: String, seq: Int = 1, period: Int = 2, clock: String = "4:12") -> Play {
    Play(id: "\(seq)", sequence: seq, kind: .other, text: text, period: period, clock: clock)
}

@Test func trackerFirstMFLIngestFlagsNothing() {
    var t = InjuryTracker()
    t.ingest(mfl: ["1": InjuryReport(status: "Questionable")], started: { _ in true })
    let s = t.status(for: love, gameID: "g")
    #expect(s.report?.code == "Q")
    #expect(!s.changedInGame)
}

@Test func trackerMFLChangeAfterKickoffFlags() {
    var t = InjuryTracker()
    t.ingest(mfl: ["1": InjuryReport(status: "Questionable")], started: { _ in true })
    t.ingest(mfl: ["1": InjuryReport(status: "Out")], started: { _ in true })
    let s = t.status(for: love, gameID: "g")
    #expect(s.report?.code == "O")
    #expect(s.changedInGame)
}

@Test func trackerMFLChangeBeforeKickoffDoesNotFlag() {
    var t = InjuryTracker()
    t.ingest(mfl: ["1": InjuryReport(status: "Questionable")], started: { _ in false })
    t.ingest(mfl: ["1": InjuryReport(status: "Out")], started: { _ in false })
    #expect(!t.status(for: love, gameID: "g").changedInGame)
}

@Test func trackerMFLDesignationDisappearingDoesNotFlag() {
    var t = InjuryTracker()
    t.ingest(mfl: ["1": InjuryReport(status: "Questionable")], started: { _ in true })
    t.ingest(mfl: [:], started: { _ in true })
    let s = t.status(for: love, gameID: "g")
    #expect(s.report == nil)
    #expect(!s.changedInGame)
}

@Test func trackerESPNChangeBetweenIngestsFlags() {
    var t = InjuryTracker()
    t.ingest(espn: ["100": InjuryReport(status: "Questionable")], gameID: "g")
    var s = t.status(for: love, gameID: "g")
    #expect(s.report?.code == "Q")
    #expect(!s.changedInGame)   // first sighting

    t.ingest(espn: ["100": InjuryReport(status: "Questionable")], gameID: "g")
    #expect(!t.status(for: love, gameID: "g").changedInGame)   // unchanged

    t.ingest(espn: ["100": InjuryReport(status: "Out")], gameID: "g")
    s = t.status(for: love, gameID: "g")
    #expect(s.report?.code == "O")
    #expect(s.changedInGame)
}

@Test func trackerESPNNewEntryOnLaterIngestFlags() {
    var t = InjuryTracker()
    t.ingest(espn: [:], gameID: "g")
    t.ingest(espn: ["100": InjuryReport(status: "Questionable")], gameID: "g")
    #expect(t.status(for: love, gameID: "g").changedInGame)
}

@Test func trackerPlayByPlayInjuryFlagsMatchingPlayer() {
    var t = InjuryTracker()
    t.ingest(plays: [play("(Shotgun) GB-J.Love pass incomplete. GB-J.Love was injured during the play.")], gameID: "g")
    let s = t.status(for: love, gameID: "g")
    #expect(s.changedInGame)
    #expect(s.note?.contains("Q2 4:12") == true)
    #expect(!t.status(for: penix, gameID: "g").changedInGame)
}

@Test func trackerPlayByPlayMatchesSuffixInsensitively() {
    var t = InjuryTracker()
    t.ingest(plays: [play("ATL-M.Penix was injured during the play.")], gameID: "g")
    #expect(t.status(for: penix, gameID: "g").changedInGame)
}

@Test func trackerReturnClearsFlagButKeepsNote() {
    var t = InjuryTracker()
    t.ingest(plays: [
        play("GB-J.Love was injured during the play.", seq: 1),
        play("** Injury Update: GB-J.Love has returned to the game. **", seq: 2, period: 3, clock: "10:00"),
    ], gameID: "g")
    let s = t.status(for: love, gameID: "g")
    #expect(!s.changedInGame)
    #expect(s.note?.contains("returned") == true)
}

@Test func trackerInjuryUpdateWithoutReturnStaysFlagged() {
    var t = InjuryTracker()
    t.ingest(plays: [
        play("GB-J.Love was injured during the play.", seq: 1),
        play("** Injury Update: GB-J.Love is questionable to return (knee). **", seq: 2),
    ], gameID: "g")
    let s = t.status(for: love, gameID: "g")
    #expect(s.changedInGame)
    #expect(s.note?.contains("questionable to return") == true)
}

@Test func trackerNeverMatchesTeamDefense() {
    var t = InjuryTracker()
    t.ingest(plays: [play("GB-J.Love was injured during the play.")], gameID: "g")
    let s = t.status(for: defense, gameID: "g")
    #expect(s.isEmpty)
}

@Test func trackerIgnoresOtherGames() {
    var t = InjuryTracker()
    t.ingest(plays: [play("GB-J.Love was injured during the play.")], gameID: "g1")
    #expect(!t.status(for: love, gameID: "g2").changedInGame)
    #expect(t.status(for: love, gameID: nil).isEmpty)
}

@Test func playByPlayInjuryMatchesTeamNotJustName() {
    // Week 8: Baltimore's Lamar Jackson was hurt while Buffalo's Landon Jackson was on the field.
    let lamar = FantasyPlayer(id: "1", name: "Jackson, Lamar", position: "QB", team: NFLTeam(mfl: "BAL"))
    let landon = FantasyPlayer(id: "2", name: "Jackson, Landon", position: "DE", team: NFLTeam(mfl: "BUF"))
    var tracker = InjuryTracker()
    tracker.ingest(plays: [Play(id: "p1", sequence: 1, kind: .other,
                                text: "L.Jackson scrambles to BLT 30 for 2 yards. BLT-L.Jackson was injured during the play.")],
                   gameID: "G")
    #expect(tracker.status(for: lamar, gameID: "G").changedInGame)
    #expect(tracker.status(for: landon, gameID: "G").isEmpty)
}
