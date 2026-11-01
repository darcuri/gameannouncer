import GameDayCore
import SwiftUI

/// Every NFL game this week, with which of my (and my opponents') starters are in it.
struct NFLGamesView: View {
    @Environment(LiveSession.self) private var session

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: 12)], spacing: 12) {
                ForEach(session.games, id: \.id) { game in
                    GameCard(game: game)
                }
            }
            .padding(16)
        }
        .overlay {
            if session.games.isEmpty {
                ContentUnavailableView("No games loaded yet", systemImage: "football")
            }
        }
    }
}

private struct GameCard: View {
    @Environment(LiveSession.self) private var session
    let game: GameState

    var body: some View {
        let starters = session.starters(in: game)
        VStack(alignment: .leading, spacing: 6) {
            TeamLine(side: game.away, game: game)
            TeamLine(side: game.home, game: game)
            HStack {
                Text(game.statusText)
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(game.phase == .live ? Color.green : Color.secondary)
                Spacer()
                if game.phase == .live, game.inRedZone, let team = game.possessionTeam {
                    Text("\(team.code) RED ZONE")
                        .font(.caption.bold())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.red, in: Capsule())
                        .foregroundStyle(.white)
                }
            }
            if !starters.mine.isEmpty {
                PlayersLine(label: "Mine", players: starters.mine, color: .accentColor)
            }
            if !starters.opponents.isEmpty {
                PlayersLine(label: "Opp", players: starters.opponents, color: .orange)
            }
        }
        .padding(12)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(starters.mine.isEmpty ? Color.clear : Color.accentColor.opacity(0.6), lineWidth: 1.5)
        }
    }
}

private struct TeamLine: View {
    let side: GameState.Side
    let game: GameState

    var body: some View {
        let hasBall = game.phase == .live && game.possessionESPNID == side.espnID
        let winning = side.score > (side.espnID == game.away.espnID ? game.home.score : game.away.score)
        HStack {
            Text(side.team.code)
                .font(.headline.monospaced())
                .frame(width: 44, alignment: .leading)
            Text("\(side.location) \(side.nickname)")
                .lineLimit(1)
                .foregroundStyle(.secondary)
            if hasBall {
                Image(systemName: "football.fill")
                    .font(.caption)
                    .foregroundStyle(game.inRedZone ? .red : .brown)
            }
            Spacer()
            if game.phase != .scheduled {
                Text("\(side.score)")
                    .font(.title2.bold().monospacedDigit())
                    .foregroundStyle(winning || game.phase != .final ? Color.primary : Color.secondary)
            }
        }
    }
}

private struct PlayersLine: View {
    let label: String
    let players: [FantasyPlayer]
    let color: Color

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(label)
                .font(.caption2.bold())
                .foregroundStyle(color)
                .frame(width: 30, alignment: .leading)
            Text(players.map(\.displayName).joined(separator: ", "))
                .font(.caption)
                .lineLimit(2)
        }
    }
}
