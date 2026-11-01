import Foundation

/// Turns events into the sentences GameAnnouncer speaks.
public enum Announcement {
    /// Just the play and the score. Fantasy involvement decides whether an event is spoken
    /// (see `FantasyContext.isRelevant`), but isn't read out. `names` expands ESPN's
    /// abbreviated play-by-play names ("T.Parker") for sack calls.
    public static func text(for event: GameEvent, names: PlayerNames? = nil) -> String {
        // Names like "Michael Penix Jr." already end the sentence.
        sentence(for: event, names: names).replacingOccurrences(of: "..", with: ".")
    }

    private static func sentence(for event: GameEvent, names: PlayerNames?) -> String {
        let game = event.game
        let team = event.team
        let opponent = team.map { $0.espnID == game.away.espnID ? game.home : game.away }
        let name = team.map(fullName) ?? fullName(game.home)
        let score = scoreLine(event)

        switch event.kind {
        case .touchdown:
            let scoreAfter = event.tryPending ? "" : score
            if let team, let returnTD = returnTouchdown(event, scoringTeam: team) {
                return "Touchdown, \(returnTD).\(scoreAfter)"
            }
            return "Touchdown, \(name)! \(playText(event))\(scoreAfter)"
        case .fieldGoal:
            return "Field goal, \(name). \(playText(event))\(score)"
        case .safety:
            return "Safety! Two points for \(name).\(score)"
        case .otherScore:
            return "Score for \(name). \(playText(event))\(score)"
        case .tryFailed:
            return "\(name) misses the try after the touchdown.\(score)"
        case .twoPointGood:
            return "Two-point conversion is good for \(name).\(score)"
        case .sack:
            return sack(event, defense: team, offense: opponent, names: names)
        case .interception:
            return interception(event, defense: team, offense: opponent, names: names)
        case .fumbleLost:
            return fumble(event, defense: team, offense: opponent, names: names)
        case .redZone:
            return "\(name) in the red zone against the \(opponent.map(fullName) ?? "defense")."
        case .kickoff:
            return "Kickoff: \(fullName(game.away)) at \(fullName(game.home))."
        case .halftime:
            return "Halftime, \(fullName(game.away)) at \(fullName(game.home)).\(score)"
        case .final:
            return "Final, \(fullName(game.away)) at \(fullName(game.home)).\(score)"
        case .scoreCorrection:
            return "Score correction, \(fullName(game.away)) at \(fullName(game.home)).\(score)"
        }
    }

    /// "Dallas Cowboys": always the full name, so two-team cities are never ambiguous.
    static func fullName(_ side: GameState.Side) -> String { "\(side.location) \(side.nickname)" }

    // MARK: Sacks

    /// "Sack, Buffalo Bills, Joe Fagnano sacked by T.J. Parker for 2 yards."
    static func sack(_ event: GameEvent, defense: GameState.Side?, offense: GameState.Side?, names: PlayerNames?) -> String {
        let teamName = defense.map(fullName) ?? "the defense"
        guard let text = event.play.map(finalCall),
              let match = text.firstMatch(of: sackPattern),
              let qb = match.output[1].substring,
              let tacklers = match.output[3].substring
        else { return "Sack, \(teamName)." }

        let defenders = tacklers
            .replacingOccurrences(of: "sack split by ", with: "")
            .replacingOccurrences(of: " and ", with: ",")
            .split(separator: ",")
            .map { expand($0, defense, names) }
            .filter { !$0.isEmpty }

        let yards = match.output[2].substring.flatMap { Int($0) }.map(abs) ?? 0
        let loss = switch yards {
        case 0: "for no gain"
        case 1: "for 1 yard"
        default: "for \(yards) yards"
        }
        let by = defenders.isEmpty ? "" : " by \(defenders.joined(separator: " and "))"
        return "Sack, \(teamName), \(expand(qb, offense, names)) sacked\(by) \(loss)."
    }

    // "(Shotgun) J.Fagnano sacked at BLT 28 for -2 yards (T.Parker)." / "... for no gain (A.B, C.D)."
    nonisolated(unsafe) private static let sackPattern =
        try! Regex(#"(\S+) sacked .*?for (?:(-?\d+) yards?|no gain)\s*\(([^)]*)\)"#)

    // MARK: Turnovers

    /// "Interception, Arizona Cardinals, S.James picks off Jacoby Brissett."
    static func interception(_ event: GameEvent, defense: GameState.Side?, offense: GameState.Side?, names: PlayerNames?) -> String {
        let teamName = defense.map(fullName) ?? "the defense"
        guard let text = event.play.map(finalCall),
              let match = text.firstMatch(of: interceptionPattern),
              let passer = match.output[1].substring,
              let defender = match.output[2].substring
        else { return "Interception, \(teamName)." }
        return "Interception, \(teamName), \(expand(defender, defense, names)) picks off \(expand(passer, offense, names))."
    }

    // "J.Brissett pass short middle intended for E.Higgins INTERCEPTED by S.James [R.Gary] at ARZ 38."
    nonisolated(unsafe) private static let interceptionPattern =
        try! Regex(#"(\S+) pass .*?INTERCEPTED by (\S+)"#)

    /// "Fumble, Javonte Williams fumbles and is recovered by Arizona Cardinals Baron Browning."
    static func fumble(_ event: GameEvent, defense: GameState.Side?, offense: GameState.Side?, names: PlayerNames?) -> String {
        let teamName = defense.map(fullName) ?? "the defense"
        guard let text = event.play.map(finalCall), let fumbles = text.range(of: "FUMBLES") else {
            return "Fumble, recovered by \(teamName)."
        }
        // The fumbler is the last ball carrier named before FUMBLES; tacklers are in
        // parentheses or brackets, so drop those first.
        let lead = text[..<fumbles.lowerBound].replacing(bracketedPattern, with: "")
        let fumbler = lead.matches(of: playerPattern).last.map { expand(lead[$0.range], offense, names) }

        var recoverer: String?
        if let match = text[fumbles.upperBound...].firstMatch(of: recoveredPattern),
           let name = match.output[1].substring {
            recoverer = expand(name, defense, names)
        }

        let who = fumbler.map { "\($0) fumbles" } ?? "Fumble"
        let by = recoverer.map { "\(teamName) \($0)" } ?? teamName
        return fumbler == nil ? "Fumble, recovered by \(by)." : "Fumble, \(who) and is recovered by \(by)."
    }

    nonisolated(unsafe) private static let bracketedPattern = try! Regex(#"\([^)]*\)|\[[^\]]*\]"#)
    // ESPN's abbreviated names: "J.Williams", "Ja.Smith", "A.St. Brown"
    nonisolated(unsafe) private static let playerPattern = try! Regex(#"\b[A-Z][a-zA-Z]*\.[A-Z][\w'-]+"#)
    // "RECOVERED by DAL-J.Mitchell at ARZ -2." (case varies; team prefix optional)
    nonisolated(unsafe) private static let recoveredPattern =
        try! Regex(#"(?i:recovered) by (?:[A-Z]{2,4}-)?([A-Z][a-zA-Z]*\.[A-Z][\w'-]+)"#)

    /// After a replay review ESPN keeps the original call and appends the corrected one
    /// ("…the play was REVERSED.(Shotgun) J.Allen pass…"); only the last call counts.
    private static func finalCall(_ play: Play) -> String {
        guard let reversed = play.text.range(of: "REVERSED.", options: .backwards) else { return play.text }
        return String(play.text[reversed.upperBound...])
    }

    private static func expand(_ abbreviated: Substring, _ side: GameState.Side?, _ names: PlayerNames?) -> String {
        let raw = abbreviated.trimmingCharacters(in: CharacterSet(charactersIn: " []."))
        return names?.fullName(raw, team: side?.team) ?? raw
    }

    // MARK: Defensive and return touchdowns

    private enum ReturnKind {
        case defense(String)       // spoken phrase: "interception", "fumble recovery"
        case specialTeams(String)  // "kickoff return", "punt return", ...
    }

    // Longest first, so "Blocked Punt Return" wins over "Punt Return".
    private static let returnPhrases: [(espn: String, kind: ReturnKind)] = [
        ("Blocked Field Goal Return", .specialTeams("blocked field goal return")),
        ("Missed Field Goal Return", .specialTeams("missed field goal return")),
        ("Blocked Punt Return", .specialTeams("blocked punt return")),
        ("Blocked Punt Recovery", .specialTeams("blocked punt recovery")),
        ("Interception Return", .defense("interception")),
        ("Fumble Return", .defense("fumble recovery")),
        ("Fumble Recovery", .defense("fumble recovery")),
        ("Kickoff Return", .specialTeams("kickoff return")),
        ("Punt Return", .specialTeams("punt return")),
    ]

    /// Words in ESPN summary text that end a previous clause, so the scorer's name is what
    /// follows the last of them: "Javonte Williams 2 Yd Rush Javonte Williams Fumble James Mitchell".
    private static let clauseEnds = ["Fumble", "Rush", "Return", "Recovery", "Interception", "Lateral"]

    /// "Carolina Panthers Defense, Joe Player, 46 yard interception"
    /// "Carolina Panthers, Joe Returner, 80 yard kickoff return"
    /// Nil for ordinary offensive touchdowns.
    private static func returnTouchdown(_ event: GameEvent, scoringTeam: GameState.Side) -> String? {
        guard let play = event.play else { return nil }
        let text = stripTry(play.text.trimmingCharacters(in: .whitespaces)).text
        for (espn, kind) in returnPhrases {
            guard let range = text.range(of: " Yd \(espn)", options: .backwards) else { continue }
            let before = text[..<range.lowerBound].split(separator: " ")
            guard let yardsWord = before.last, let yards = Int(yardsWord) else { continue }
            let nameWords = before.dropLast().reversed().prefix { !clauseEnds.contains(String($0)) }.reversed()
            let scorer = nameWords.joined(separator: " ")

            let phrase: String
            var teamName = fullName(scoringTeam)
            switch kind {
            case let .defense(spoken):
                phrase = spoken
                // A fumble the offense recovers in the end zone is still an offensive score.
                if play.offenseTeamID != scoringTeam.espnID { teamName += " Defense" }
            case let .specialTeams(spoken):
                phrase = spoken
            }
            let distance = yards == 0 ? "\(phrase) in the end zone" : "\(yards) yard \(phrase)"
            return scorer.isEmpty ? "\(teamName), \(distance)" : "\(teamName), \(scorer), \(distance)"
        }
        return nil
    }

    // MARK: Shared

    /// " Bengals lead 13 to 7." / " Tied at 7." / " Bills win 27 to 19."
    static func scoreLine(_ event: GameEvent) -> String {
        let (away, home) = (event.awayScore, event.homeScore)
        if away == home { return " Tied at \(away)." }
        let (leader, high, low) = away > home
            ? (fullName(event.game.away), away, home)
            : (fullName(event.game.home), home, away)
        let verb = event.kind == .final ? "win" : "lead"
        return " \(leader) \(verb) \(high) to \(low)."
    }

    /// Splits "… (Evan McPherson Kick)" off the end. `failed`/`twoPoint` describe the try.
    private static func stripTry(_ text: String) -> (text: String, paren: String?) {
        guard let open = text.lastIndex(of: "("), text.hasSuffix(")") else { return (text, nil) }
        return (text[..<open].trimmingCharacters(in: .whitespaces), text[open...].lowercased())
    }

    /// ESPN summary text tidied for speech: "Ja'Marr Chase 30 yard pass from Joe Burrow."
    /// The kicker parenthetical is dropped unless the try failed.
    static func playText(_ event: GameEvent) -> String {
        guard let raw = event.play?.text.trimmingCharacters(in: .whitespaces), !raw.isEmpty else { return "" }
        var (text, paren) = stripTry(raw)
        var suffix = ""
        if let paren {
            let failed = paren.contains("fail") || paren.contains("no good") || paren.contains("blocked")
            if paren.contains("two-point") || paren.contains("2pt") {
                suffix = failed ? " Two-point try failed." : " Two-point conversion good."
            } else if failed {
                suffix = " Extra point no good."
            }
        }
        for (abbrev, spoken) in spokenTerms {
            text = text.replacingOccurrences(of: abbrev, with: spoken)
        }
        if !text.hasSuffix(".") { text += "." }
        return text + suffix
    }

    private static let spokenTerms = [
        (" Yd Rush", " yard run"),
        (" Yd Field Goal", " yard field goal"),
        (" Yd Interception Return", " yard interception return"),
        (" Yd Fumble Return", " yard fumble return"),
        (" Yd Fumble Recovery", " yard fumble recovery"),
        (" Yd Kickoff Return", " yard kickoff return"),
        (" Yd Punt Return", " yard punt return"),
        (" Yd ", " yard "),
    ]
}
