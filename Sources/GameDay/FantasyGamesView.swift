import GameDayCore
import SwiftUI

/// Matchup list on the left, the selected matchup's starters side by side on the right.
struct FantasyGamesView: View {
    @Environment(LiveSession.self) private var session
    @ViewState private var selection: Int? = 0

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
    @ViewState private var showBench = false

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

    private func sorted(_ scores: [LiveScoring.PlayerScore]) -> [LiveScoring.PlayerScore] {
        scores.sorted { positionRank($0) < positionRank($1) }
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
        // Two lines per player (name, then team and game status) so names get the full width.
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
                            Text(player?.displayName ?? "Player \(score.id)")
                                .lineLimit(1)
                            if let player, let game, game.phase == .live, game.possessionTeam == player.team {
                                Image(systemName: "football.fill")
                                    .font(.caption2)
                                    .foregroundStyle(game.inRedZone ? .red : .brown)
                                    .help(game.inRedZone ? "In the red zone" : "Has the ball")
                            }
                        }
                        HStack(spacing: 6) {
                            Text(player?.team.code ?? "")
                                .foregroundStyle(.secondary)
                            GameStatusText(game: game, secondsRemaining: score.gameSecondsRemaining)
                        }
                        .font(.caption)
                    }
                    Spacer(minLength: 8)
                    Text(score.score, format: .number.precision(.fractionLength(2)))
                        .monospacedDigit()
                }
            }
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
