import Foundation
import GameAnnouncerCore
import Observation

/// Event types the user can mute separately.
enum SpokenCategory: String, CaseIterable, Identifiable {
    case scoring, turnovers, sacks, redZone, gameStatus

    var id: String { rawValue }

    var label: String {
        switch self {
        case .scoring: "Scores"
        case .turnovers: "Turnovers"
        case .sacks: "Sacks"
        case .redZone: "Red zone"
        case .gameStatus: "Kickoff, half & final"
        }
    }

    init(_ kind: GameEvent.Kind) {
        switch kind {
        case .touchdown, .fieldGoal, .safety, .otherScore, .tryFailed, .twoPointGood, .scoreCorrection: self = .scoring
        case .interception, .fumbleLost: self = .turnovers
        case .sack: self = .sacks
        case .redZone: self = .redZone
        case .kickoff, .halftime, .final: self = .gameStatus
        }
    }
}

struct LogEntry: Identifiable {
    let id = UUID()
    let time: Date
    let event: GameEvent
    let text: String
    let involvesMine: Bool
    let involvesOpponent: Bool
    let spoken: Bool
}

/// Owns polling, event detection and announcements for one league + franchise.
@MainActor
@Observable
final class LiveSession {
    /// `-demo YES`: show DemoData instead of a real league, with no network access and
    /// without saving any settings.
    static let isDemo = UserDefaults.standard.bool(forKey: "demo")

    // MARK: Settings (persisted, except in demo mode)

    var leagueID: String? = isDemo ? "DEMO" : UserDefaults.standard.string(forKey: "leagueID") {
        didSet { Self.save(leagueID, "leagueID") }
    }
    var franchiseID: String? = isDemo ? DemoData.myFranchise : UserDefaults.standard.string(forKey: "franchiseID") {
        didSet { Self.save(franchiseID, "franchiseID") }
    }
    var scope = FantasyContext.Scope(rawValue: UserDefaults.standard.string(forKey: "scope") ?? "") ?? .myGames {
        didSet { Self.save(scope.rawValue, "scope") }
    }
    var muted = isDemo || UserDefaults.standard.bool(forKey: "muted") {
        didSet {
            Self.save(muted, "muted")
            if muted { speaker.stop() }
        }
    }
    var mutedCategories = Set((UserDefaults.standard.stringArray(forKey: "mutedCategories") ?? []).compactMap(SpokenCategory.init)) {
        didSet { Self.save(mutedCategories.map(\.rawValue), "mutedCategories") }
    }

    private static func save(_ value: Any?, _ key: String) {
        guard !isDemo else { return }
        UserDefaults.standard.set(value, forKey: key)
    }

    var isConfigured: Bool { leagueID != nil && franchiseID != nil }

    var selectedTab = RootTab.fantasy

    // MARK: Live state

    private(set) var league: FantasyLeague?
    private(set) var week: Int?
    private(set) var liveScoring: LiveScoring?
    private(set) var breakdowns = ScoringBreakdowns(byPlayer: [:])
    private(set) var games: [GameState] = []
    private(set) var log: [LogEntry] = []
    private(set) var players: PlayerDatabase?
    private(set) var context: FantasyContext?
    private(set) var lastUpdate: Date?
    private(set) var nextRefresh: Date?
    private(set) var refreshInterval: TimeInterval = 30
    private(set) var statusMessage = "Starting…"
    private(set) var errorMessage: String?

    let speaker = Speaker()

    private var differ = EventDiffer()
    private var names: PlayerNames?
    private var mfl: MFLClient?
    private let espn = ESPNClient(userAgent: LiveSession.userAgent)
    private var loop: Task<Void, Never>?
    private var pause: Task<Void, Never>?

    static let userAgent = ProcessInfo.processInfo.environment["MFL_USER_AGENT"] ?? "GameAnnouncer/0.1"

    // MARK: Lifecycle

    func start() {
        guard loop == nil, isConfigured else { return }
        if Self.isDemo {
            loadDemo()
            return
        }
        loop = Task { await run() }
    }

    private func loadDemo() {
        league = DemoData.league
        week = 8
        players = DemoData.players
        names = PlayerNames(DemoData.players)
        liveScoring = DemoData.liveScoring
        breakdowns = DemoData.breakdowns
        context = FantasyContext(franchiseID: DemoData.myFranchise, liveScoring: DemoData.liveScoring,
                                 players: DemoData.players)
        games = DemoData.games
        for event in DemoData.events { record(event) }
        lastUpdate = DemoData.now
        // Start the refresh countdown partway through, like a live session between updates.
        refreshInterval = 30
        nextRefresh = Date.now.addingTimeInterval(19)
        statusMessage = "Live"
    }

    func restart() {
        loop?.cancel()
        pause?.cancel()
        loop = nil
        differ = EventDiffer()
        log = []
        league = nil
        liveScoring = nil
        breakdowns = ScoringBreakdowns(byPlayer: [:])
        games = []
        start()
    }

    /// Skip the rest of the current wait and refresh now.
    func refreshNow() {
        pause?.cancel()
    }

    private func run() async {
        guard let leagueID else { return }
        do {
            statusMessage = "Loading league…"
            let probe = MFLClient(year: Calendar.current.component(.year, from: .now), leagueID: leagueID,
                                  apiKey: ProcessInfo.processInfo.environment["MFL_APIKEY"], userAgent: Self.userAgent)
            let status = try await probe.status()
            let year = Int(status.year) ?? Calendar.current.component(.year, from: .now)
            week = status.liveScoringWeek
            let client = MFLClient(year: year, leagueID: leagueID,
                                   apiKey: ProcessInfo.processInfo.environment["MFL_APIKEY"], userAgent: Self.userAgent)
            mfl = client
            league = try JSONDecoder().decode(FantasyLeague.self, from: try await client.league())
            statusMessage = "Loading players…"
            let db = try await loadPlayers(client: client, year: year)
            players = db
            names = PlayerNames(db)
            errorMessage = nil
        } catch {
            errorMessage = "Couldn't load league: \(error)"
            statusMessage = "Stopped"
            loop = nil
            return
        }

        while !Task.isCancelled {
            await refresh()
            let live = games.contains { $0.phase == .live || $0.phase == .halftime }
            refreshInterval = live ? 30 : nextQuietInterval()
            nextRefresh = Date.now.addingTimeInterval(refreshInterval)
            await sleep(refreshInterval)
        }
    }

    /// Between game windows, wake shortly before the next kickoff (at most every 5 minutes).
    private func nextQuietInterval() -> TimeInterval {
        let upcoming = games.filter { $0.phase == .scheduled }.compactMap(\.kickoff).filter { $0 > .now }.min()
        guard let upcoming else { return 300 }
        return min(max(upcoming.timeIntervalSinceNow - 30, 30), 300)
    }

    private func sleep(_ seconds: TimeInterval) async {
        let pause = Task<Void, Never> { try? await Task.sleep(for: .seconds(seconds)) }
        self.pause = pause
        await pause.value
    }

    private func refresh() async {
        guard let mfl, let week else { return }
        statusMessage = "Updating…"
        var problems: [String] = []
        var events: [GameEvent] = []
        let now = Date.now

        do {
            let board = try JSONDecoder().decode(ESPNScoreboard.self, from: try await espn.scoreboard())
            games = board.games.sorted { ($0.kickoff ?? .distantFuture, $0.id) < ($1.kickoff ?? .distantFuture, $1.id) }
            events += differ.ingest(scoreboard: board.games, at: now)

            let liveIDs = board.events.filter(\.isLive).map(\.id)
            let espn = self.espn
            let summaries = await withTaskGroup(of: ESPNSummary?.self) { group in
                for id in liveIDs {
                    group.addTask { try? JSONDecoder().decode(ESPNSummary.self, from: await espn.summary(eventID: id)) }
                }
                var results: [ESPNSummary] = []
                for await summary in group {
                    if let summary { results.append(summary) }
                }
                return results
            }
            for summary in summaries {
                events += differ.ingest(plays: summary.plays, gameID: summary.eventID, at: now)
            }
        } catch {
            problems.append("ESPN: \(error)")
        }

        do {
            let live = try JSONDecoder().decode(LiveScoring.self, from: try await mfl.liveScoring(week: week))
            liveScoring = live
            if let franchiseID, let players {
                context = FantasyContext(franchiseID: franchiseID, liveScoring: live, players: players)
            }
            // Best effort: the page is HTML, and private leagues may not serve it to the app.
            // Keep the last breakdowns rather than flagging every refresh as partial.
            if let page = try? await mfl.liveScoringPage(week: week) {
                let parsed = ScoringBreakdowns(liveScoringPage: page)
                if !parsed.byPlayer.isEmpty { breakdowns = parsed }
            }
        } catch {
            problems.append("MFL: \(error)")
        }

        for event in events { record(event) }
        lastUpdate = .now
        errorMessage = problems.isEmpty ? nil : problems.joined(separator: " · ")
        statusMessage = problems.isEmpty ? "Live" : "Partial update"
    }

    private func record(_ event: GameEvent) {
        let involvement = context?.involvement(in: event) ?? []
        let relevant = context?.isRelevant(event, scope: scope) ?? true
        let speak = relevant && !muted && !mutedCategories.contains(SpokenCategory(event.kind))
        let text = Announcement.text(for: event, names: names)
        log.insert(LogEntry(time: event.observedAt, event: event, text: text,
                            involvesMine: involvement.contains(where: \.isMine),
                            involvesOpponent: involvement.contains { !$0.isMine },
                            spoken: speak), at: 0)
        if speak { speaker.say(text) }
    }

    // MARK: Player database cache

    private func loadPlayers(client: MFLClient, year: Int) async throws -> PlayerDatabase {
        let dir = URL.applicationSupportDirectory.appending(path: "GameAnnouncer")
        let file = dir.appending(path: "players-\(year).json")
        let attributes = try? FileManager.default.attributesOfItem(atPath: file.path(percentEncoded: false))
        if let modified = attributes?[.modificationDate] as? Date, modified.timeIntervalSinceNow > -86_400,
           let data = try? Data(contentsOf: file),
           let db = try? JSONDecoder().decode(PlayerDatabase.self, from: data) {
            return db
        }
        let data = try await client.players()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? data.write(to: file)
        return try JSONDecoder().decode(PlayerDatabase.self, from: data)
    }

    // MARK: Lookups for views

    func player(_ id: String) -> FantasyPlayer? { players?.players[id] }

    func game(for team: NFLTeam) -> GameState? { games.first { $0.teams.contains(team) } }

    func franchiseName(_ id: String) -> String { league?.franchiseName(id) ?? "Team \(id)" }

    /// My matchups first, then the rest in MFL's order.
    var matchups: [LiveScoring.Matchup] {
        let all = liveScoring?.matchups ?? []
        guard let franchiseID else { return all }
        return all.filter { $0.franchises.contains { $0.id == franchiseID } }
            + all.filter { !$0.franchises.contains { $0.id == franchiseID } }
    }

    func starters(in game: GameState) -> (mine: [FantasyPlayer], opponents: [FantasyPlayer]) {
        let teams = Set(game.teams)
        return ((context?.myStarters ?? []).filter { teams.contains($0.team) },
                (context?.opponentStarters ?? []).filter { teams.contains($0.team) })
    }
}
