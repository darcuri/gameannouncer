import Foundation
import GameDayCore

// Records raw MFL + ESPN responses during live games, so EventDiffer can be built and
// tested against real snapshot sequences.
//
// Usage: gameday-record [--league ID] [--week N] [--year YYYY] [--out DIR]
//                       [--interval SECS] [--summary-interval SECS] [--once] [--no-espn]
// Env:   MFL_APIKEY (private leagues), MFL_USER_AGENT (registered client name)

struct Options {
    var league: String?
    var week: Int?
    var year = Calendar(identifier: .gregorian).component(.year, from: .now)
    var out = URL(filePath: "Fixtures")
    var interval: Duration = .seconds(30)
    var summaryInterval: TimeInterval = 120
    var once = false
    var espn = true

    static func parse(_ args: [String]) -> Options {
        var o = Options()
        var it = args.dropFirst().makeIterator()
        while let arg = it.next() {
            func value() -> String {
                guard let v = it.next() else { fail("missing value for \(arg)") }
                return v
            }
            switch arg {
            case "--league": o.league = value()
            case "--week": o.week = Int(value())
            case "--year": o.year = Int(value()) ?? o.year
            case "--out": o.out = URL(filePath: value())
            case "--interval": o.interval = .seconds(Int(value()) ?? 30)
            case "--summary-interval": o.summaryInterval = TimeInterval(value()) ?? 120
            case "--once": o.once = true
            case "--no-espn": o.espn = false
            default: fail("unknown argument \(arg)")
            }
        }
        return o
    }
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("error: \(message)\n".utf8))
    exit(2)
}

func log(_ message: String) {
    let stamp = Date.now.formatted(date: .omitted, time: .standard)
    print("[\(stamp)] \(message)")
}

/// Writes each response under <out>/<year>-W<week>/<source>/<UTC timestamp>.json,
/// skipping bodies identical to the last one written for that source.
final class FixtureWriter {
    let root: URL
    private var last: [String: Data] = [:]
    private let stamp: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        return f
    }()

    init(root: URL) { self.root = root }

    /// Returns true if a new file was written.
    @discardableResult
    func record(_ source: String, _ data: Data) throws -> Bool {
        if last[source] == data { return false }
        last[source] = data
        let dir = root.appending(path: source)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try data.write(to: dir.appending(path: "\(stamp.string(from: .now)).json"))
        return true
    }

    func recordOnce(_ name: String, _ data: Data) throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try data.write(to: root.appending(path: "\(name).json"))
    }
}

/// Minimal peek at an ESPN summary to decide whether it's worth saving.
struct SummarySignature: Decodable, Equatable {
    struct Play: Decodable, Equatable { let id: String }
    let scoringPlays: [Play]?
}

// Flush each log line even when stdout is redirected to a file.
setlinebuf(stdout)

let options = Options.parse(CommandLine.arguments)
let userAgent = ProcessInfo.processInfo.environment["MFL_USER_AGENT"] ?? "GameDayMac-spike/0.1"
let mfl = MFLClient(
    year: options.year,
    leagueID: options.league,
    apiKey: ProcessInfo.processInfo.environment["MFL_APIKEY"],
    userAgent: userAgent
)
let espn = ESPNClient(userAgent: userAgent)

let week: Int
if let w = options.week {
    week = w
} else {
    guard let w = try await mfl.status().liveScoringWeek else { fail("couldn't determine live scoring week") }
    week = w
}

let writer = FixtureWriter(root: options.out.appending(path: "\(options.year)-W\(String(format: "%02d", week))"))
log("recording week \(week) to \(writer.root.path(percentEncoded: false))")

// One-off reference data.
if let league = options.league {
    try writer.recordOnce("league-\(league)", try await mfl.league())
    try writer.recordOnce("projectedScores-\(league)", try await mfl.projectedScores(week: week))
}
try writer.recordOnce("players", try await mfl.players())

var schedETag: String?
var schedule: NFLSchedule?
var summaryState: [String: (signature: SummarySignature, savedAt: Date, final: Bool)] = [:]

while true {
    var notes: [String] = []
    do {
        switch try await mfl.nflSchedule(week: week, etag: schedETag) {
        case .notModified:
            notes.append("nfl_sched 304")
        case let .fetched(data, etag):
            schedETag = etag
            schedule = try JSONDecoder().decode(NFLSchedule.self, from: data)
            if try writer.record("nfl_sched", data) { notes.append("nfl_sched ✎") }
        }

        if let league = options.league {
            if try writer.record("liveScoring-\(league)", try await mfl.liveScoring(week: week)) {
                notes.append("liveScoring ✎")
            }
        }

        if options.espn {
            let boardData = try await espn.scoreboard()
            if try writer.record("espn_scoreboard", boardData) { notes.append("scoreboard ✎") }
            let board = try JSONDecoder().decode(ESPNScoreboard.self, from: boardData)
            for event in board.events where event.isLive || (event.isFinal && summaryState[event.id]?.final == false) {
                let data = try await espn.summary(eventID: event.id)
                let sig = try JSONDecoder().decode(SummarySignature.self, from: data)
                let prev = summaryState[event.id]
                let due = prev == nil
                    || prev!.signature != sig
                    || Date.now.timeIntervalSince(prev!.savedAt) >= options.summaryInterval
                    || event.isFinal
                if due, try writer.record("espn_summary/\(event.id)", data) {
                    notes.append("\(event.shortName) ✎")
                    summaryState[event.id] = (sig, .now, event.isFinal)
                }
            }
        }
    } catch {
        notes.append("error: \(error)")
    }

    let live = schedule?.liveGames() ?? []
    log("\(live.count) live · " + (notes.isEmpty ? "no changes" : notes.joined(separator: ", ")))

    if options.once { break }

    // Poll fast while games are on; otherwise sleep until shortly before the next kickoff.
    if !live.isEmpty {
        try await Task.sleep(for: options.interval)
    } else if let next = schedule?.nextKickoff() {
        let wait = max(Int(next.timeIntervalSinceNow) - 60, 30)
        let capped = min(wait, 15 * 60)
        log("no live games; next kickoff \(next.formatted(date: .abbreviated, time: .shortened)), sleeping \(capped)s")
        try await Task.sleep(for: .seconds(capped))
    } else if schedule != nil {
        log("no live or upcoming games this week; done")
        break
    } else {
        try await Task.sleep(for: options.interval)
    }
}
