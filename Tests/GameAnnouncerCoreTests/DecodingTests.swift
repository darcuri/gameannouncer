import Foundation
import Testing
@testable import GameAnnouncerCore

@Test func scheduleDecodesSingleMatchupAsArray() throws {
    let json = """
    {"nflSchedule":{"week":"8","matchup":{"status":"INPROG","kickoff":"1793556000","gameSecondsRemaining":"1800",
     "team":[{"id":"BUF","score":"14","hasPossession":"1","inRedZone":"1","isHome":"1"},
             {"id":"BAL","score":"","hasPossession":"0","inRedZone":"0","isHome":"0"}]}}}
    """
    let schedule = try JSONDecoder().decode(NFLSchedule.self, from: Data(json.utf8))
    #expect(schedule.games.count == 1)
    let game = try #require(schedule.games.first)
    #expect(game.status == .inProgress)
    #expect(game.gameSecondsRemaining == 1800)
    #expect(game.team[0].score == 14)
    #expect(game.team[1].score == nil)
}

@Test func scheduleTreatsPastKickoffAsLive() throws {
    let json = """
    {"nflSchedule":{"week":"8","matchup":[
     {"status":"SCHED","kickoff":"100","gameSecondsRemaining":"3600","team":[{"id":"A","score":""},{"id":"B","score":""}]},
     {"status":"SCHED","kickoff":"9999999999","gameSecondsRemaining":"3600","team":[{"id":"C","score":""},{"id":"D","score":""}]},
     {"status":"FINAL","kickoff":"50","gameSecondsRemaining":"0","team":[{"id":"E","score":"3"},{"id":"F","score":"7"}]}]}}
    """
    let schedule = try JSONDecoder().decode(NFLSchedule.self, from: Data(json.utf8))
    let now = Date(timeIntervalSince1970: 1000)
    #expect(schedule.liveGames(at: now).map { $0.team[0].id } == ["A"])
    #expect(schedule.nextKickoff(after: now) == Date(timeIntervalSince1970: 9999999999))
}
