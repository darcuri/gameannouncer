import Foundation
import GameAnnouncerCore

// Replays fixtures written by gameannouncer-record through EventDiffer and prints (or speaks)
// what GameAnnouncer would have announced.
//
// Usage: gameannouncer-replay <week dir> [--franchise ID] [--scope all|myGames|myPlayers]
//                       [--max-age SECS] [--speak] [--voice NAME] [--from HH:MM] [--to HH:MM]

struct Options {
    var dir: URL?
    var franchise: String?
    var scope = FantasyContext.Scope.all
    var maxAge: TimeInterval = 300
    var speak = false
    var voice: String?
    var from: String?
    var to: String?

    static func parse(_ args: [String]) -> Options {
        var o = Options()
        var it = args.dropFirst().makeIterator()
        while let arg = it.next() {
            func value() -> String {
                guard let v = it.next() else { fail("missing value for \(arg)") }
                return v
            }
            switch arg {
            case "--franchise": o.franchise = value()
            case "--scope":
                let v = value()
                guard let s = FantasyContext.Scope(rawValue: v) else { fail("unknown scope \(v)") }
                o.scope = s
            case "--max-age": o.maxAge = TimeInterval(value()) ?? 300
            case "--speak": o.speak = true
            case "--voice": o.voice = value()
            case "--from": o.from = value()
            case "--to": o.to = value()
            default:
                guard !arg.hasPrefix("--"), o.dir == nil else { fail("unknown argument \(arg)") }
                o.dir = URL(filePath: arg)
            }
        }
        return o
    }
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("error: \(message)\n".utf8))
    exit(2)
}

/// One recorded file. Sources sort scoreboard → summary → liveScoring at the same second,
/// so plays are matched against the freshest game state.
struct Snapshot {
    enum Source: Int { case scoreboard, summary, liveScoring }
    let time: Date
    let source: Source
    let url: URL
}

let stampFormat: DateFormatter = {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.timeZone = TimeZone(identifier: "UTC")
    f.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
    return f
}()

func snapshots(in dir: URL, source: Snapshot.Source) -> [Snapshot] {
    let files = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: nil)?
        .compactMap { $0 as? URL }
        .filter { $0.pathExtension == "json" } ?? []
    return files.compactMap { url in
        stampFormat.date(from: url.deletingPathExtension().lastPathComponent)
            .map { Snapshot(time: $0, source: source, url: url) }
    }
}

/// "13:05" → that wall-clock time (local) on the day of `reference`.
func clockTime(_ hhmm: String?, on reference: Date) -> Date? {
    guard let hhmm else { return nil }
    let parts = hhmm.split(separator: ":").compactMap { Int($0) }
    guard parts.count == 2 else { fail("expected HH:MM, got \(hhmm)") }
    return Calendar.current.date(bySettingHour: parts[0], minute: parts[1], second: 0, of: reference)
}

func speak(_ text: String, voice: String?) {
    let say = Process()
    say.executableURL = URL(filePath: "/usr/bin/say")
    say.arguments = (voice.map { ["-v", $0] } ?? []) + [text]
    try? say.run()
    say.waitUntilExit()
}

let options = Options.parse(CommandLine.arguments)
guard let dir = options.dir else { fail("usage: gameannouncer-replay <week dir> [options]") }

let fm = FileManager.default
let leagueDirs = (try? fm.contentsOfDirectory(atPath: dir.path(percentEncoded: false)))?
    .filter { $0.hasPrefix("liveScoring-") } ?? []

var all = snapshots(in: dir.appending(path: "espn_scoreboard"), source: .scoreboard)
    + snapshots(in: dir.appending(path: "espn_summary"), source: .summary)
    + leagueDirs.flatMap { snapshots(in: dir.appending(path: $0), source: .liveScoring) }
all.sort { ($0.time, $0.source.rawValue) < ($1.time, $1.source.rawValue) }
guard let first = all.first else { fail("no fixtures under \(dir.path(percentEncoded: false))") }

let from = clockTime(options.from, on: first.time)
let to = clockTime(options.to, on: first.time)

let players: PlayerDatabase? = {
    guard let data = fm.contents(atPath: dir.appending(path: "players.json").path(percentEncoded: false)) else {
        if options.franchise != nil { fail("players.json missing; needed for --franchise") }
        return nil
    }
    return try? JSONDecoder().decode(PlayerDatabase.self, from: data)
}()
let names = players.map(PlayerNames.init)

var differ = EventDiffer(maxPlayAge: options.maxAge)
var context: FantasyContext?
let decoder = JSONDecoder()
let clock = Date.FormatStyle(date: .omitted, time: .standard)
var spoken = 0

for snapshot in all {
    if let to, snapshot.time > to { break }
    guard let data = fm.contents(atPath: snapshot.url.path(percentEncoded: false)) else { continue }

    let events: [GameEvent]
    do {
        switch snapshot.source {
        case .scoreboard:
            events = differ.ingest(scoreboard: try decoder.decode(ESPNScoreboard.self, from: data).games, at: snapshot.time)
        case .summary:
            let summary = try decoder.decode(ESPNSummary.self, from: data)
            events = differ.ingest(plays: summary.plays, gameID: summary.eventID, at: snapshot.time)
        case .liveScoring:
            if let franchise = options.franchise, let players {
                let live = try decoder.decode(LiveScoring.self, from: data)
                context = FantasyContext(franchiseID: franchise, liveScoring: live, players: players)
            }
            events = []
        }
    } catch {
        print("! \(snapshot.url.lastPathComponent): \(error)")
        continue
    }

    // Before --from, keep feeding state but stay quiet.
    if let from, snapshot.time < from { continue }

    for event in events {
        if let context, !context.isRelevant(event, scope: options.scope) { continue }
        let involvement = context?.involvement(in: event) ?? []
        let text = Announcement.text(for: event, names: names)
        let marker = involvement.contains(where: \.isMine) ? "★" : involvement.isEmpty ? " " : "☆"
        print("[\(snapshot.time.formatted(clock))] \(marker) \(text)")
        if options.speak { speak(text, voice: options.voice) }
        spoken += 1
    }
}

print("— \(spoken) announcements")
