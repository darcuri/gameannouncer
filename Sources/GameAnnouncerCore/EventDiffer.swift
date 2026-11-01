import Foundation

/// Something worth telling the user about.
public struct GameEvent: Sendable, Equatable {
    public enum Kind: Sendable, Equatable {
        case touchdown, fieldGoal, safety, otherScore
        /// Follow-ups to a touchdown announced before its try was known.
        case tryFailed, twoPointGood
        case sack, interception, fumbleLost
        case redZone
        case kickoff, halftime, final
        case scoreCorrection
    }

    public var kind: Kind
    /// The game as last seen on the scoreboard (team names, phase).
    public var game: GameState
    /// The team that did the thing: scored, got the sack or takeaway, or entered the red zone.
    public var team: GameState.Side?
    public var play: Play?
    public var awayScore: Int
    public var homeScore: Int
    public var observedAt: Date
    /// A touchdown posted before its extra point or two-point try; the score will change.
    public var tryPending = false

    public init(kind: Kind, game: GameState, team: GameState.Side?, play: Play?,
                awayScore: Int, homeScore: Int, observedAt: Date, tryPending: Bool = false) {
        self.kind = kind
        self.game = game
        self.team = team
        self.play = play
        self.awayScore = awayScore
        self.homeScore = homeScore
        self.observedAt = observedAt
        self.tryPending = tryPending
    }
}

/// Turns successive scoreboard and play-by-play snapshots into events. Pure state machine:
/// feed it snapshots in the order they were fetched, and it returns only what's new.
///
/// Rules:
/// - The first scoreboard snapshot of a game only seeds state.
/// - Plays are deduplicated by ESPN play ID. A play older than `maxPlayAge` (by ESPN's
///   wallclock) is recorded but not announced, so launching mid-game or recovering from a
///   gap doesn't read out the whole first half.
/// - A play that turns into a scoring play later (after review) is announced then.
/// - The scoring team is whichever side's score rose versus the previous play, which gets
///   defensive and return touchdowns right without parsing text.
/// - ESPN posts a touchdown before its try (+6), then updates the score in place, and often
///   never updates the text. A +6 touchdown is held as pending; once later plays exist, the
///   score at the latest play says how the try went. Only failures and two-point
///   conversions get a follow-up, since a made kick is the default.
/// - ESPN briefly drops possession after scores and timeouts, then restores it with a stale
///   red-zone flag. During extra-point tries and kickoffs it reports no down (-1) while
///   showing the scoring team "in the red zone" at the try spot. Neither kind of snapshot
///   says anything about a drive, so both leave the stored possession and red zone alone.
public struct EventDiffer: Sendable {
    public var maxPlayAge: TimeInterval

    private struct PendingTry: Sendable {
        var gameID: String
        var scoredAway: Bool
        var scoreBefore: Int
    }

    private var games: [String: GameState] = [:]
    private var seenPlays: [String: Set<String>] = [:]
    private var announcedScoring: Set<String> = []
    private var pendingTries: [String: PendingTry] = [:]

    public init(maxPlayAge: TimeInterval = 300) {
        self.maxPlayAge = maxPlayAge
    }

    public func game(_ id: String) -> GameState? { games[id] }

    public mutating func ingest(scoreboard: [GameState], at now: Date) -> [GameEvent] {
        var events: [GameEvent] = []
        for var game in scoreboard {
            guard let prev = games[game.id] else {
                games[game.id] = game
                continue
            }
            if game.possessionESPNID == nil || !game.isLiveDown {
                game.possessionESPNID = prev.possessionESPNID
                game.inRedZone = prev.inRedZone
            }
            defer { games[game.id] = game }

            func event(_ kind: GameEvent.Kind, team: GameState.Side? = nil) -> GameEvent {
                GameEvent(kind: kind, game: game, team: team, play: nil,
                          awayScore: game.away.score, homeScore: game.home.score, observedAt: now)
            }

            switch (prev.phase, game.phase) {
            case (.scheduled, .live): events.append(event(.kickoff))
            case (.live, .halftime): events.append(event(.halftime))
            case (.live, .final), (.halftime, .final): events.append(event(.final))
            default: break
            }

            if game.away.score < prev.away.score || game.home.score < prev.home.score {
                events.append(event(.scoreCorrection))
            }

            let enteredRedZone = game.inRedZone
                && !(prev.inRedZone && prev.possessionESPNID == game.possessionESPNID)
            if enteredRedZone, game.phase == .live, let team = game.side(espnID: game.possessionESPNID) {
                events.append(event(.redZone, team: team))
            }
        }
        return events
    }

    public mutating func ingest(plays: [Play], gameID: String, at now: Date) -> [GameEvent] {
        let firstSight = seenPlays[gameID] == nil
        var seen = seenPlays[gameID] ?? []
        defer { seenPlays[gameID] = seen }
        guard let game = games[gameID] else {
            // Can't name teams yet; remember the plays so they aren't announced late.
            seen.formUnion(plays.map(\.id))
            announcedScoring.formUnion(plays.filter(\.kind.isScoring).map(\.id))
            return []
        }

        var events = resolveTries(plays: plays, game: game, now: now)
        for (index, play) in plays.enumerated() {
            let isNew = seen.insert(play.id).inserted
            let newlyScoring = play.kind.isScoring && !announcedScoring.contains(play.id)
            guard isNew || newlyScoring else { continue }
            if play.kind.isScoring { announcedScoring.insert(play.id) }

            guard let kind = Self.eventKind(play.kind) else { continue }
            guard isFresh(play, now: now, firstSight: firstSight) else { continue }

            let previous = index > 0 ? plays[index - 1] : nil
            let team: GameState.Side?
            var tryPending = false
            if play.kind.isScoring {
                team = scoringSide(play, previous: previous, game: game)
                if play.kind == .touchdown, let team {
                    let scoredAway = team.espnID == game.away.espnID
                    let before = scoredAway ? previous?.awayScore ?? 0 : previous?.homeScore ?? 0
                    let after = scoredAway ? play.awayScore : play.homeScore
                    if after - before == 6, !Self.tryFailedInText(play) {
                        pendingTries[play.id] = PendingTry(gameID: game.id, scoredAway: scoredAway, scoreBefore: before)
                        tryPending = true
                    }
                }
            } else {
                // Sacks and takeaways are credited to the defense.
                team = [game.away, game.home].first { $0.espnID != play.offenseTeamID }
            }
            events.append(GameEvent(kind: kind, game: game, team: team, play: play,
                                    awayScore: play.awayScore, homeScore: play.homeScore,
                                    observedAt: now, tryPending: tryPending))
        }
        return events
    }

    private mutating func resolveTries(plays: [Play], game: GameState, now: Date) -> [GameEvent] {
        var events: [GameEvent] = []
        for (id, pending) in pendingTries where pending.gameID == game.id {
            guard let index = plays.firstIndex(where: { $0.id == id }) else { continue }
            let play = plays[index]
            let latest = plays.last!
            let failedInText = Self.tryFailedInText(play)
            guard failedInText || index < plays.count - 1 else { continue } // nothing after it yet

            pendingTries[id] = nil
            let scoreNow = pending.scoredAway ? latest.awayScore : latest.homeScore
            let kind: GameEvent.Kind?
            switch scoreNow - pending.scoreBefore {
            case _ where failedInText: kind = .tryFailed
            case 6: kind = .tryFailed
            case 8: kind = .twoPointGood
            default: kind = nil // made kick, or the other team scored again already
            }
            if let kind {
                events.append(GameEvent(
                    kind: kind, game: game, team: pending.scoredAway ? game.away : game.home, play: play,
                    awayScore: latest.awayScore, homeScore: latest.homeScore, observedAt: now))
            }
        }
        return events
    }

    private static func tryFailedInText(_ play: Play) -> Bool {
        guard let open = play.text.lastIndex(of: "(") else { return false }
        let paren = play.text[open...].lowercased()
        return paren.contains("fail") || paren.contains("no good") || paren.contains("blocked")
    }

    private func isFresh(_ play: Play, now: Date, firstSight: Bool) -> Bool {
        guard let wallclock = play.wallclock else { return !firstSight }
        return now.timeIntervalSince(wallclock) <= maxPlayAge
    }

    private func scoringSide(_ play: Play, previous: Play?, game: GameState) -> GameState.Side? {
        let awayDelta = play.awayScore - (previous?.awayScore ?? 0)
        let homeDelta = play.homeScore - (previous?.homeScore ?? 0)
        if awayDelta > 0, awayDelta >= homeDelta { return game.away }
        if homeDelta > 0 { return game.home }
        return game.side(espnID: play.offenseTeamID)
    }

    private static func eventKind(_ kind: PlayKind) -> GameEvent.Kind? {
        switch kind {
        case .touchdown: .touchdown
        case .fieldGoal: .fieldGoal
        case .safety: .safety
        case .otherScore: .otherScore
        case .sack: .sack
        case .interception: .interception
        case .fumbleLost: .fumbleLost
        case .other: nil
        }
    }
}
