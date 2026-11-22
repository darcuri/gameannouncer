import GameAnnouncerCore
import SwiftUI

/// Popover from a player's name: injury status, then ESPN's latest news for the player.
struct PlayerNewsView: View {
    @Environment(LiveSession.self) private var session
    let player: FantasyPlayer

    private enum Load {
        case loading
        case loaded([PlayerNewsItem])
        case failed(String)
    }

    @State private var load = Load.loading

    var body: some View {
        let status = session.status(for: player)
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(player.displayName).font(.headline)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            if !status.isEmpty {
                StatusLine(status: status)
            }
            if player.espnID != nil {
                Divider()
                news
                if let url = espnURL {
                    Divider()
                    Link("Open on ESPN", destination: url).font(.caption)
                }
            }
        }
        .textSelection(.enabled)
        .padding(14)
        .frame(width: 380)
        .frame(maxHeight: 420)
        .task(id: player.id) {
            // Team defenses have no ESPN athlete, hence no news.
            guard player.espnID != nil else { return }
            do {
                load = .loaded(try await session.news(for: player))
            } catch is CancellationError {
            } catch {
                load = .failed(error.localizedDescription)
            }
        }
    }

    /// "WR · CIN · #1"
    private var subtitle: String {
        [player.position, player.team.code, player.jersey.map { "#\($0)" }]
            .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
    }

    private var espnURL: URL? {
        player.espnID.flatMap { URL(string: "https://www.espn.com/nfl/player/_/id/\($0)") }
    }

    @ViewBuilder private var news: some View {
        switch load {
        case .loading:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Loading news…").foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 60)
        case .failed(let message):
            Text("Couldn't load news: \(message)")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        case .loaded(let items) where items.isEmpty:
            Text("No recent news").font(.callout).foregroundStyle(.secondary)
        case .loaded(let items):
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(items) { item in
                        NewsItemView(item: item)
                        if item.id != items.last?.id { Divider() }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

private struct StatusLine: View {
    let status: PlayerStatus

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            InjuryBadge(status: status)
            VStack(alignment: .leading, spacing: 2) {
                if let report = status.report {
                    Text(report.summary).fontWeight(.semibold)
                }
                if let note = status.note {
                    Text(note).font(.callout)
                }
                if status.changedInGame {
                    Text("Changed during the game").font(.caption)
                }
            }
            .foregroundStyle(status.changedInGame ? Color.red : Color.primary)
            .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct NewsItemView: View {
    let item: PlayerNewsItem

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(item.headline).bold()
                .fixedSize(horizontal: false, vertical: true)
            Text(byline).font(.caption).foregroundStyle(.secondary)
            if let body = item.body {
                Text(body).font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let link = item.link {
                Link("Read more", destination: link).font(.caption)
            }
        }
    }

    /// "3 hours ago · Rotowire"
    private var byline: String {
        [item.published.map { $0.formatted(.relative(presentation: .named)) },
         item.source.isEmpty ? nil : item.source]
            .compactMap { $0 }.joined(separator: " · ")
    }
}
