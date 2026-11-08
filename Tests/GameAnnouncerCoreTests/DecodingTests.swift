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

@Test func scoringBreakdownsParseLiveScoringPage() {
    // Shapes from MFL's live_scoring_summary page: entity-encoded titles, line breaks inside
    // a line, a player listed twice, and a player with no stats yet ("-", no link).
    let html = """
    <td class="points" id="points_14777"><a href="javascript:void(0);" onclick="alert(this.title);" title='&bull;4.00 pts for 1 Passing TDs &#xA;&bull;7.95 pts for 159 Passing Yards &#xA;&bull;-2.00 pts for 1 Interceptions &#xA;'>9.95</a></td>
    <td class="points" id="points_16583"><a href="javascript:void(0);" title='&bull;2.65 pts for 53&#xA; Passing Yards &#xA;'>2.65</a></td>
    <td class="points" id="points_12611">-</td>
    <td class="points" id="points_0506"><a title='&bull;6.00 pts for 4 Point Differential &#xA;&bull;0.00 pts for 0 Sacked a QB &#xA;'>6.00</a></td>
    <td class="points" id="points_14777"><a title='&bull;1.00 pts for 1 Something Else &#xA;'>1.00</a></td>
    """
    let b = ScoringBreakdowns(liveScoringPage: html)
    #expect(b["14777"] == [
        .init(category: "Passing TDs", count: "1", points: 4),
        .init(category: "Passing Yards", count: "159", points: 7.95),
        .init(category: "Interceptions", count: "1", points: -2),
    ])
    #expect(b["16583"] == [.init(category: "Passing Yards", count: "53", points: 2.65)])
    #expect(b["12611"].isEmpty)
    #expect(b["0506"].map(\.category) == ["Point Differential", "Sacked a QB"])
}
