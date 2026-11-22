import AppKit
import GameAnnouncerCore
import SwiftUI

/// Matchup list on the left, the selected matchup's starters side by side on the right.
struct FantasyGamesView: View {
    @Environment(LiveSession.self) private var session
    @State private var selection: Int? = 0

    var body: some View {
        let matchups = session.matchups
        HSplitView {
            List(selection: $selection) {
                ForEach(matchups.indices, id: \.self) { index in
                    MatchupRow(matchup: matchups[index])
                        .tag(index)
                }
            }
            .frame(minWidth: 240, idealWidth: 270, maxWidth: 360)

            Group {
                if let index = selection ?? (matchups.isEmpty ? nil : 0), matchups.indices.contains(index) {
                    MatchupDetail(matchup: matchups[index])
                } else {
                    ContentUnavailableView("Waiting for live scoring", systemImage: "sportscourt")
                }
            }
            .frame(minWidth: 600, maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct MatchupRow: View {
    @Environment(LiveSession.self) private var session
    let matchup: LiveScoring.Matchup

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(ordered, id: \.id) { franchise in
                HStack {
                    Text(session.franchiseName(franchise.id))
                        .fontWeight(franchise.id == session.franchiseID ? .bold : .regular)
                        .lineLimit(1)
                    Spacer()
                    Text(franchise.score, format: .number.precision(.fractionLength(2)))
                        .monospacedDigit()
                        .fontWeight(isLeading(franchise) ? .semibold : .regular)
                }
            }
        }
        .padding(.vertical, 3)
    }

    /// Away team on top, like a scoreboard.
    private var ordered: [LiveScoring.Franchise] {
        matchup.franchises.sorted { !$0.isHome && $1.isHome }
    }

    private func isLeading(_ franchise: LiveScoring.Franchise) -> Bool {
        matchup.franchises.allSatisfy { $0.id == franchise.id || $0.score < franchise.score }
    }
}

private struct MatchupDetail: View {
    @Environment(LiveSession.self) private var session
    let matchup: LiveScoring.Matchup

    var body: some View {
        ScrollView {
            HStack(alignment: .top, spacing: 16) {
                ForEach(matchup.franchises.sorted { !$0.isHome && $1.isHome }, id: \.id) { franchise in
                    TeamColumn(franchise: franchise, leading: isLeading(franchise))
                }
            }
            .padding(16)
        }
    }

    private func isLeading(_ franchise: LiveScoring.Franchise) -> Bool {
        matchup.franchises.allSatisfy { $0.id == franchise.id || $0.score < franchise.score }
    }
}

private struct TeamColumn: View {
    @Environment(LiveSession.self) private var session
    let franchise: LiveScoring.Franchise
    let leading: Bool
    @State private var showBench = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(session.franchiseName(franchise.id))
                    .font(.title3.bold())
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Text(franchise.score, format: .number.precision(.fractionLength(2)))
                    .font(.system(size: 30, weight: .bold).monospacedDigit())
                    .foregroundStyle(leading ? Color.primary : Color.secondary)
            }
            Text("\(franchise.playersCurrentlyPlaying) playing · \(franchise.playersYetToPlay) yet to play")
                .font(.callout)
                .foregroundStyle(.secondary)

            Divider()
            PlayerTable(players: sorted(franchise.starters))

            DisclosureGroup("Bench (\(franchise.bench.count))", isExpanded: $showBench) {
                PlayerTable(players: sorted(franchise.bench))
                    .opacity(0.75)
            }
            .font(.callout)
        }
        .padding(12)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 8))
        .frame(maxWidth: .infinity)
    }

    /// Position, then name, then ID: MFL reorders its list as scores change, so anything less
    /// than a total order makes rows within a position jump around.
    private func sorted(_ scores: [LiveScoring.PlayerScore]) -> [LiveScoring.PlayerScore] {
        scores.sorted { a, b in
            let (rankA, rankB) = (positionRank(a), positionRank(b))
            if rankA != rankB { return rankA < rankB }
            let (nameA, nameB) = (session.player(a.id)?.name ?? "", session.player(b.id)?.name ?? "")
            if nameA != nameB { return nameA.localizedStandardCompare(nameB) == .orderedAscending }
            return a.id < b.id
        }
    }

    private func positionRank(_ score: LiveScoring.PlayerScore) -> Int {
        let order = ["QB", "RB", "WR", "TE", "PK", "Def"]
        return order.firstIndex(of: session.player(score.id)?.position ?? "") ?? order.count
    }
}

private struct PlayerTable: View {
    @Environment(LiveSession.self) private var session
    let players: [LiveScoring.PlayerScore]

    var body: some View {
        // Name, then team or NFL score and game status, then points by scoring category,
        // each on its own line so names get the full width.
        VStack(alignment: .leading, spacing: 8) {
            ForEach(players, id: \.id) { score in
                let player = session.player(score.id)
                let game = player.flatMap { session.game(for: $0.team) }
                HStack(alignment: .center, spacing: 10) {
                    Text(player?.position ?? "")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                        .frame(width: 30, alignment: .leading)
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 4) {
                            if let player {
                                PlayerName(player: player)
                            } else {
                                Text("Player \(score.id)").lineLimit(1)
                            }
                            if let player, let game, game.phase == .live, game.possessionTeam == player.team {
                                Image(systemName: "football.fill")
                                    .font(.caption2)
                                    .foregroundStyle(game.inRedZone ? .red : .brown)
                                    .help(game.inRedZone ? "In the red zone" : "Has the ball")
                            }
                        }
                        HStack(spacing: 6) {
                            if let player, let game, game.phase != .scheduled {
                                GameScoreText(game: game, team: player.team)
                            } else {
                                Text(player?.team.code ?? "")
                                    .foregroundStyle(.secondary)
                            }
                            GameStatusText(game: game, secondsRemaining: score.gameSecondsRemaining)
                        }
                        .font(.caption)
                        BreakdownText(lines: session.breakdowns[score.id].filter { $0.points != 0 })
                    }
                    Spacer(minLength: 8)
                    Text(score.score, format: .number.precision(.fractionLength(2)))
                        .monospacedDigit()
                }
            }
        }
    }
}

/// The player's name, jersey number and injury badge. The name opens recent news (or, for
/// team defenses, which ESPN has no news for, just the injury status when there is one).
private struct PlayerName: View {
    @Environment(LiveSession.self) private var session
    let player: FantasyPlayer
    @State private var showNews = false
    @State private var hovering = false

    var body: some View {
        let status = session.status(for: player)
        HStack(spacing: 4) {
            if player.espnID != nil || !status.isEmpty {
                Button { showNews = true } label: { name(status) }
                    .buttonStyle(.plain)
                    .onHover { inside in
                        hovering = inside
                        if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
                    }
                    .onDisappear { if hovering { NSCursor.pop(); hovering = false } }
                    .popover(isPresented: $showNews, arrowEdge: .bottom) {
                        PlayerNewsView(player: player)
                    }
            } else {
                name(status)
            }
            if session.showJerseyNumbers, let jersey = player.jersey, !jersey.isEmpty {
                Text("#\(jersey)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            InjuryBadge(status: status)
        }
    }

    private func name(_ status: PlayerStatus) -> some View {
        Text(player.displayName)
            .lineLimit(1)
            .underline(hovering)
            .foregroundStyle(status.changedInGame ? Color.red : Color.primary)
    }
}

/// "Q" / "O" / "IR" in a small capsule, or a cross when there's only a play-by-play note.
struct InjuryBadge: View {
    let status: PlayerStatus

    var body: some View {
        if let report = status.report {
            Text(report.code)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(Self.color(report.code), in: RoundedRectangle(cornerRadius: 3))
                .help([report.summary, status.note].compactMap { $0 }.joined(separator: "\n"))
        } else if let note = status.note {
            Image(systemName: "cross.case.fill")
                .font(.caption2)
                .foregroundStyle(status.changedInGame ? .red : .orange)
                .help(note)
        }
    }

    /// Orange for "might play", red for "won't".
    static func color(_ code: String) -> Color {
        ["Q", "P", "DTD"].contains(code) ? .orange : .red
    }
}

/// "BUF 17, MIA 10", away team first, with the player's team emphasized.
private struct GameScoreText: View {
    let game: GameState
    let team: NFLTeam

    var body: some View {
        HStack(spacing: 0) {
            side(game.away)
            Text(", ").foregroundStyle(.secondary)
            side(game.home)
        }
        .font(.caption.monospacedDigit())
        .lineLimit(1)
    }

    private func side(_ side: GameState.Side) -> some View {
        Text("\(side.team.code) \(side.score)")
            .foregroundStyle(side.team == team ? Color.primary : Color.secondary)
            .fontWeight(side.team == team ? .semibold : .regular)
    }
}

/// "159 Passing Yards 7.95 · 1 Passing TDs 4.00", wrapping as needed.
private struct BreakdownText: View {
    let lines: [ScoringBreakdowns.Line]

    var body: some View {
        if !lines.isEmpty {
            lines.enumerated().reduce(Text("")) { text, item in
                let (index, line) = item
                let points = line.points.formatted(.number.precision(.fractionLength(2)))
                return text
                    + Text(index == 0 ? "" : "  ·  ")
                    // Non-breaking spaces, so lines wrap between items, not inside one.
                    + Text("\(line.count) \(line.category) ".replacingOccurrences(of: " ", with: "\u{00A0}"))
                    + Text(points).foregroundColor(line.points < 0 ? .red : .primary).monospacedDigit()
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct GameStatusText: View {
    let game: GameState?
    let secondsRemaining: Int

    var body: some View {
        Group {
            if let game {
                Text(game.statusText)
                    .foregroundStyle(game.phase == .live ? Color.green : Color.secondary)
            } else {
                Text(secondsRemaining == 0 ? "Bye" : "—").foregroundStyle(.secondary)
            }
        }
        .font(.caption.monospacedDigit())
        .lineLimit(1)
    }
}
