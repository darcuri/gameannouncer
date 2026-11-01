import GameDayCore
import SwiftUI

/// Everything GameDay noticed, newest first. Spoken entries get a speaker icon.
struct PlayLogView: View {
    @Environment(LiveSession.self) private var session
    @ViewState private var scoringOnly = true

    var body: some View {
        let entries = session.log.filter { !scoringOnly || SpokenCategory($0.event.kind) == .scoring }
        VStack(spacing: 0) {
            HStack {
                Picker("Show", selection: $scoringOnly) {
                    Text("Scores").tag(true)
                    Text("All plays").tag(false)
                }
                .pickerStyle(.segmented)
                .fixedSize()
                Spacer()
                Text("\(entries.count) entries").foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            List(entries) { entry in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(entry.time.formatted(date: .omitted, time: .shortened))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 64, alignment: .leading)
                    Image(systemName: icon(entry.event.kind))
                        .foregroundStyle(color(entry.event.kind))
                        .frame(width: 18)
                    Text(entry.text)
                        .fontWeight(entry.involvesMine ? .semibold : .regular)
                    Spacer()
                    if entry.involvesMine {
                        Text("Mine").font(.caption2.bold()).foregroundStyle(Color.accentColor)
                    } else if entry.involvesOpponent {
                        Text("Opp").font(.caption2.bold()).foregroundStyle(.orange)
                    }
                    if entry.spoken {
                        Image(systemName: "speaker.wave.2").foregroundStyle(.secondary).help("Announced")
                    }
                }
            }
            .overlay {
                if entries.isEmpty {
                    ContentUnavailableView("Nothing yet", systemImage: "list.bullet",
                                           description: Text("Plays appear here as they happen."))
                }
            }
        }
    }

    private func icon(_ kind: GameEvent.Kind) -> String {
        switch SpokenCategory(kind) {
        case .scoring: "flag.checkered"
        case .turnovers: "arrow.triangle.2.circlepath"
        case .sacks: "figure.american.football"
        case .redZone: "exclamationmark.circle"
        case .gameStatus: "clock"
        }
    }

    private func color(_ kind: GameEvent.Kind) -> Color {
        switch SpokenCategory(kind) {
        case .scoring: .green
        case .turnovers: .orange
        case .sacks: .purple
        case .redZone: .red
        case .gameStatus: .secondary
        }
    }
}

struct SettingsView: View {
    @Environment(LiveSession.self) private var session
    @ViewState private var voice = ""

    var body: some View {
        @Bindable var session = session
        Form {
            Section("League") {
                LabeledContent("League", value: session.league?.name ?? session.leagueID ?? "—")
                LabeledContent("Your team", value: session.franchiseID.map(session.franchiseName) ?? "—")
                Button("Change League…") {
                    session.leagueID = nil
                    session.franchiseID = nil
                    session.restart()
                }
            }
            Section("Announcements") {
                Picker("Announce", selection: $session.scope) {
                    Text("All NFL games").tag(FantasyContext.Scope.all)
                    Text("Games with my or my opponents' starters").tag(FantasyContext.Scope.myGames)
                    Text("Plays by my or my opponents' starters").tag(FantasyContext.Scope.myPlayers)
                }
                ForEach(SpokenCategory.allCases) { category in
                    Toggle(category.label, isOn: Binding(
                        get: { !session.mutedCategories.contains(category) },
                        set: { on in
                            if on { session.mutedCategories.remove(category) } else { session.mutedCategories.insert(category) }
                        }
                    ))
                }
                Picker("Voice", selection: $voice) {
                    Text("System default").tag("")
                    ForEach(Speaker.englishVoices, id: \.identifier) { v in
                        Text("\(v.name) (\(v.language))").tag(v.identifier)
                    }
                }
                .onChange(of: voice) { session.speaker.voiceIdentifier = voice.isEmpty ? nil : voice }
                Button("Test Voice") { session.speaker.say("Touchdown, Carolina Panthers Defense, Jaycee Horn, 46 yard interception.") }
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
        .onAppear { voice = session.speaker.voiceIdentifier ?? "" }
    }
}
