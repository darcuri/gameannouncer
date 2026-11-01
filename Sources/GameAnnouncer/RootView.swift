import GameAnnouncerCore
import SwiftUI

enum RootTab: String, CaseIterable {
    case fantasy, nfl, plays
}

struct RootView: View {
    @Environment(LiveSession.self) private var session

    var body: some View {
        @Bindable var session = session
        VStack(spacing: 0) {
            if session.isConfigured {
                TabView(selection: $session.selectedTab) {
                    FantasyGamesView()
                        .tabItem { Text("Fantasy Games") }
                        .tag(RootTab.fantasy)
                    NFLGamesView()
                        .tabItem { Text("NFL Games") }
                        .tag(RootTab.nfl)
                    PlayLogView()
                        .tabItem { Text("Touchdowns & Plays") }
                        .tag(RootTab.plays)
                }
                .padding(.top, 6)
            } else {
                LeagueSetupView()
            }
            Divider()
            StatusBar()
        }
        .navigationTitle(session.league.map { "GameAnnouncer — \($0.name)" } ?? "GameAnnouncer")
        .navigationSubtitle(session.week.map { "Week \($0)" } ?? "")
        .toolbar {
            if session.isConfigured {
                ToolbarItem {
                    Picker("Announce", selection: $session.scope) {
                        Text("All games").tag(FantasyContext.Scope.all)
                        Text("My games").tag(FantasyContext.Scope.myGames)
                        Text("My players").tag(FantasyContext.Scope.myPlayers)
                    }
                    .pickerStyle(.segmented)
                    .help("Which plays are announced out loud")
                }
                ToolbarItem {
                    Toggle(isOn: $session.muted) {
                        Label("Mute", systemImage: session.muted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    }
                    .help(session.muted ? "Announcements muted" : "Mute announcements")
                }
                ToolbarItem {
                    Button { session.refreshNow() } label: { Label("Refresh", systemImage: "arrow.clockwise") }
                        .help("Refresh now (⌘R)")
                }
            }
        }
        .task {
            session.start()
            await Snapshots.runIfRequested(session)
        }
    }
}

/// Bottom bar, like the original: what's happening plus a countdown to the next update.
struct StatusBar: View {
    @Environment(LiveSession.self) private var session

    var body: some View {
        HStack(spacing: 12) {
            if let error = session.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .lineLimit(1)
                    .truncationMode(.tail)
            } else {
                Text(session.statusMessage)
            }
            Spacer()
            if let last = session.lastUpdate {
                Text("Updated \(last.formatted(date: .omitted, time: .standard))")
                    .foregroundStyle(.secondary)
            }
            if let next = session.nextRefresh {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let remaining = max(0, next.timeIntervalSince(context.date))
                    HStack(spacing: 6) {
                        ProgressView(value: 1 - remaining / session.refreshInterval)
                            .progressViewStyle(.linear)
                            .tint(.red)
                            .frame(width: 120)
                        Text("\(Int(remaining.rounded()))s")
                            .monospacedDigit()
                            .frame(width: 36, alignment: .trailing)
                    }
                }
            }
        }
        .font(.callout)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.bar)
    }
}

/// The original's "Get League" tab: enter a league ID, pick your team.
struct LeagueSetupView: View {
    @Environment(LiveSession.self) private var session
    @State private var leagueID = ""
    @State private var league: FantasyLeague?
    @State private var franchiseID = ""
    @State private var loading = false
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Welcome to GameAnnouncer")
                .font(.largeTitle.bold())
            Text("Live scoring and announcements for MyFantasyLeague")
                .font(.title3)
            Text("Enter your MyFantasyLeague league ID: the 5-digit number at the end of your league's home page address.")
                .foregroundStyle(.secondary)
            HStack {
                TextField("League ID", text: $leagueID)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 140)
                    .onSubmit(load)
                Button("Find League", action: load)
                    .disabled(leagueID.count < 4 || loading)
                if loading { ProgressView().controlSize(.small) }
            }
            if let league {
                Picker("Your team in \(league.name)", selection: $franchiseID) {
                    Text("Choose…").tag("")
                    ForEach(league.franchises) { Text($0.name).tag($0.id) }
                }
                .frame(maxWidth: 420)
                Button("Start") {
                    session.leagueID = leagueID
                    session.franchiseID = franchiseID
                    session.restart()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(franchiseID.isEmpty)
            }
            if let error {
                Text(error).foregroundStyle(.red)
            }
            Spacer()
        }
        .padding(32)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func load() {
        loading = true
        error = nil
        let id = leagueID.trimmingCharacters(in: .whitespaces)
        Task {
            defer { loading = false }
            do {
                let client = MFLClient(year: Calendar.current.component(.year, from: .now), leagueID: id,
                                       userAgent: LiveSession.userAgent)
                league = try JSONDecoder().decode(FantasyLeague.self, from: try await client.league())
            } catch {
                self.error = "Couldn't load league \(id). Private leagues need MFL_APIKEY set."
            }
        }
    }
}
