# GameAnnouncer — Architecture Evaluation

## What the original did

MFL GameDay was a free, Windows-only desktop client for MyFantasyLeague:

- You entered a 5-digit league ID and clicked Start.
- It refreshed every **30–35 s** (the web live-scoring page refreshes every 90 s and stops after ~15 min idle).
- It had a fantasy matchups view and an **NFL games view**.
- It supported custom-scoring extras (home-field points, offense-minus-defense).
- It used **spoken announcements** (choice of 3 voices) for touchdowns, field goals, **Red Zone entries**, sacks, and more, for all NFL games or only games that touch your players.

Sources: [MFL GameDay page](https://home.myfantasyleague.com/game-day/), [MFL API reference](https://api.myfantasyleague.com/2025/api_info?STATE=details), [MFL FAQ 1135](https://www45.myfantasyleague.com/2025/support?FAQ=1135).

## Data sources (verified live on 2026-11-01)

| Need | Source | Notes |
|---|---|---|
| Current week | `api.myfantasyleague.com/fflnetdynamic{YEAR}/mfl_status.json` | Returns `LiveScoringWeek`, `CurrentWeek`, etc. |
| League, franchises, league host | `export?TYPE=league&L=…&JSON=1` | Gives the league's `wwwNN` host. Cache it per session. |
| Rosters / starters | `TYPE=rosters`, `TYPE=liveScoring&DETAILS=1` | |
| **Fantasy live scores** | `TYPE=liveScoring&L=…&W=…&DETAILS=1` | Per franchise: score, game seconds remaining, players yet to play / playing, per-player points. |
| Projections | `TYPE=projectedScores` | Use for win-probability or "pace". |
| Player DB | `TYPE=players&DETAILS=1` (+`SINCE=`) | Changes about once a day, so cache it on disk. Includes **`espn_id`**, `sportsdata_id`, `stats_id`, and others for cross-source matching. |
| **NFL game state** | `fflnetdynamic{YEAR}/nfl_sched_{W}.json` | A static file that does update live (unlike `TYPE=nflSchedule`, which stopped in 2020). Per game: status, score, `gameSecondsRemaining`, `hasPossession`, **`inRedZone`**. Supports **ETag/Last-Modified**, so polling it is cheap. |
| **Play-level events** (who scored, how, sacks) | ESPN unofficial `site.api.espn.com/apis/site/v2/sports/football/nfl/scoreboard` and `/summary?event={id}` | `scoringPlays[]` gives text like "Tucker Kraft 12 Yd pass from Jordan Love (… PAT Failed)". `drives` and plays cover sacks, turnovers, etc. This API is undocumented and could break. |

**Key gap:** MFL doesn't license raw NFL play-by-play to API clients, so MFL alone can't tell you *"Josh Jacobs 1-yard TD run."* You can infer events from score and fantasy-point deltas: a +6/+7 NFL score change is a TD, +3 is an FG, and an `inRedZone` 0→1 is a red-zone entry. That covers most of the original's announcements, but not sacks or the scorer's name. A second source fills that gap: ESPN, or a paid feed (SportsDataIO, Sportradar) if you want stability.

### MFL API constraints

- **Auth:** use a per-league `APIKEY` (export-only, from Help → Developer's API) or a login cookie (`MFL_USER_ID`, via HTTPS POST to `login`). Store it in the macOS Keychain.
- **Rate limits** are unpublished and lower during NFL games. Exceeding them returns HTTP 429. Register a client and send a fixed **User-Agent** to get about 2.5× the limit. Space requests about 1 s apart, don't retry on 429, and back off instead.
- This sets the poll budget. Per league every ~30 s: 1× `liveScoring`, plus 1× `nfl_sched` (conditional GET). Everything else gets cached.

### Findings from the first live recording (2026-11-01, week 8)

- **`nfl_sched_{W}.json` is too slow for announcements.** It showed every game as not started until at least 12 minutes after kickoff. Later it ran about 10 minutes behind ESPN: at 18:55 UTC its `lastUpdate` was 18:45:53, and it still showed the end of the first quarter while ESPN was in the second quarter. **ESPN's scoreboard has to be the main source for NFL game state** (score, clock, possession, red zone). Keep MFL's file only as a backup and to cross-check its week and game list.
- **`liveScoring` is reasonably current.** Fantasy points changed within about 30 seconds of the ESPN scoreboard.
- **Not every fantasy-point jump is a play.** At kickoff, every starting defense jumped by about 10 points, from "0 points allowed" scoring. The comparison logic must not treat fantasy-point changes alone as scoring plays. Announce from NFL events, then attach the fantasy impact.
- **ESPN posts touchdowns before the try.** The touchdown play first shows +6. A minute or two later, the same play ID is updated in place to +7 or +8. ESPN's `scoringPlays` list often keeps the old score and text, so take scores from the drives' play-by-play. `EventDiffer` announces a +6 touchdown without a score line, then follows up only on a missed try or a two-point conversion.
- **Possession blinks after scores and timeouts.** The scoreboard sends one snapshot with no possession, then the same team again with a stale red-zone flag. Treating "no possession" as "no change" removed the duplicate red-zone calls.
- **Play text needs care.**
  - Names are abbreviated ("T.Parker"). Expand them through MFL's player database, which includes defensive players. Match last name, first initials and team, and ignore suffixes, since ESPN drops "Jr.".
  - Reviewed plays keep the original call followed by "…REVERSED." and the corrected call; parse only the last call.
  - "RECOVERED" is usually uppercase.
  - Strip-sacks have their own play type, "Sack Opp Fumble Recovery".
  - In summary text, a defensive or return touchdown reads "Name N Yd Interception Return". A fumble the offense recovers in its own end zone also uses that wording, so compare the scoring team with the team on offense.
- **Plays in a drive aren't in order,** and the current drive can repeat the last previous one. Sort by `sequenceNumber` and remove duplicates by ID.
- **Scope matters for noise.** Across 8 early games, "all games" gave about 60 announcements in 80 minutes. Most were red-zone entries and sacks, so the app needs per-event-type toggles.

### Dev tools

- `gameannouncer-record`: saves live responses to `Fixtures/` (ignored by git).
- `gameannouncer-replay <week dir> --franchise <franchise ID> [--scope all|myGames|myPlayers] [--speak] [--from 13:00 --to 14:00]`: replays recordings through `EventDiffer` and prints or speaks the announcements.
- `GameAnnouncer` (SwiftUI app): `swift run GameAnnouncer -leagueID <league ID> -franchiseID <franchise ID>`. With no arguments it shows a league setup screen, and choices persist in UserDefaults. Add `-muted YES` for silent testing, and `-snapshotDir <folder>` to save a PNG of each tab after the first update. The snapshots draw the app's own view hierarchy and need no Screen Recording permission, but they render the tab bar blank.
  - Built with SwiftPM and Xcode's toolchain. Binaries land in `swift build --show-bin-path` (`.build/out/Products/Debug`). The Command Line Tools alone can't build the app: in this SDK `@State` is a macro whose plugin ships only with Xcode.
  - Tabs follow the original's documented views: Fantasy Games (the matchup list, with each matchup's starters side by side), NFL Games (score, clock, possession, red zone, and your and your opponents' starters in each game), and Touchdowns & Plays (the event log, with spoken entries marked). The status bar has the original's countdown to the next refresh.
- `scripts/make-app.sh [--open | --zip]`: builds `dist/GameAnnouncer.app` (universal release build for Apple Silicon and Intel, `Support/Info.plist`, bundle ID `com.darcuri.gameannouncer`, ad-hoc signed). The icon is drawn in code (`AppIcon.swift`), rendered with `GameAnnouncer --render-icon`, and packed into `AppIcon.icns`; `swift run` builds use the same artwork as their Dock icon. The bundled app keeps settings under its bundle ID and copies them over from `swift run`'s "GameAnnouncer" defaults on first launch. `--zip` also writes `dist/GameAnnouncer-<version>.zip` and its SHA-256, taking the version from `Support/Info.plist`.
- `swift test`: runs the tests.
- `scripts/configure-github.sh`: run once right after making the repo public. It applies rulesets (no force-push or deletion of `main`; pull requests with passing CI, which admins can bypass; immutable `v*` tags), secret scanning with push protection, private vulnerability reporting, Dependabot alerts, and approval before CI runs on outside contributors' pull requests. GitHub's free plan only allows these on public repos.

## Proposed architecture

Use native **Swift + SwiftUI**, macOS 14+. The app runs as a window plus a menu-bar extra, and speech comes from `AVSpeechSynthesizer`, with no extra dependencies. (Electron or Tauri would work, but they add weight and give worse system-voice access for no gain.)

```
┌──────────────────────── Providers (actors, polling) ────────────────────────┐
│ MFLClient            NFLGameFeed (MFL nfl_sched)     PlayFeed (ESPN, opt.)    │
│  league/rosters/      ETag poll 15-30s                summary per *live* game │
│  players(cache)/      → GameState snapshots          → Play snapshots        │
│  liveScoring 30s                                                              │
└───────┬──────────────────────┬───────────────────────────────┬───────────────┘
        ▼                      ▼                               ▼
┌──────────────────────── Snapshot store (in-memory, @Observable) ─────────────┐
│ League, Franchises, Matchups, Players(id-map MFL↔ESPN), NFLGames, Plays      │
└───────┬──────────────────────────────────────────────────────────────────────┘
        ▼
┌─ EventDiffer ──────────────────────────────────────────────────────────────┐
│ prev snapshot vs new → [GameEvent]: touchdown, fieldGoal, safety, redZone,  │
│ turnover, sack, gameStart/half/final, fantasyLeadChange, bigPlayerSwing     │
│ dedupe by stable key (gameId+playId or gameId+score+clock)                  │
└───────┬────────────────────────────────────────────────────────────────────┘
        ▼
┌─ RelevanceFilter ─┐   ┌─ AnnouncementQueue ───────────────────────────────┐
│ all games / my    │──▶│ priority, coalescing, rate limit, quiet mode,     │
│ games / my players│   │ templates → AVSpeechSynthesizer + optional chime  │
│ / opponent's      │   │ + UNUserNotification banner                       │
└───────────────────┘   └───────────────────────────────────────────────────┘
        ▼
┌─ SwiftUI views ─────────────────────────────────────────────────────────────┐
│ Matchups board · Matchup detail (starters, pts, yet-to-play, pace) ·        │
│ NFL games grid (score, clock, possession, red zone) · Event ticker/log ·    │
│ Menu-bar extra (my score vs opp) · Settings                                 │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Components

1. **`MFLClient` (actor).** Resolves the host, handles auth and the User-Agent, serializes requests (≥1 s apart), and backs off on 429. Its typed `Codable` models need lenient decoding, because MFL returns one-element arrays as objects and numbers as strings. Write a `@OneOrMany` property wrapper for this early.
2. **`PlayerCache`.** Store the `players` DB on disk (SQLite/GRDB or a JSON file) and refresh it daily with `SINCE`. Keep MFL→ESPN ID maps.
3. **`GameClock` / scheduler.** Poll adaptively: ~30 s (or faster for `nfl_sched` via ETag) only while a game is `INPROG`. Otherwise sleep until the next kickoff. This keeps the app quiet on Tuesdays and helps with rate limits.
4. **`EventDiffer`.** This is the core of the app and should be pure and fully unit-tested with recorded snapshots. It needs a stable dedupe key so a TD isn't announced twice, and it has to handle **score corrections and reversals**: if a TD is overturned and the score drops, emit a "correction" event or suppress it.
5. **`RelevanceFilter`.** Settings decide the scope: all games, games involving my starters, games involving my starters plus my opponent's, or my players only. It also controls which event types are spoken.
6. **`Announcer`.** A queue with priority, so your player's TD beats a random FG. It coalesces simultaneous events ("Touchdowns in Buffalo and Detroit"), uses templates, offers voice choice (`AVSpeechSynthesisVoice.speechVoices()`, including Siri/Premium voices), and can play an optional NFL-team chime. Its "Quiet" toggle lives in the menu-bar extra. Possible later addition: a fantasy context line ("…that's 9.4 points for your team, now up by 3").
7. **Persistence.** Keep settings in `UserDefaults`, secrets in Keychain, and an event log for the current week so you can see what you missed.

### Announcement fidelity tiers

| Tier | Data | Example |
|---|---|---|
| A — MFL only | `nfl_sched` + `liveScoring` deltas | "Touchdown, Green Bay. Packers lead 14–10." / "Buffalo in the red zone." / "Your player Josh Jacobs +7.2 points." |
| B — + ESPN | `summary.scoringPlays`, drives | "Touchdown Green Bay: Matthew Golden 24-yard pass from Jordan Love." / sacks / interceptions |

Ship Tier A first, then add B behind a `PlayFeed` protocol so ESPN can be swapped for a paid feed.

### Risks

- **Undocumented endpoints.** Neither the ESPN API nor MFL's `fflnetdynamic` files are formal contracts. Isolate each behind a protocol and record fixtures.
- **Latency.** MFL live data lags real TV by roughly 30–90 s. Announcements will come after the broadcast; this was also true of the original.
- **Rate limits during games.** Register the client and use adaptive polling.
- **Custom scoring.** `liveScoring` already applies league rules, so don't re-implement scoring. Only compute "pace" and projections client-side.
- **Multiple matchups per week.** Some leagues play two games a week, so the same franchise appears in two `liveScoring` matchups. Model matchups as a list per franchise, never as "my opponent".

## Suggested build order

1. CLI spike: fetch `mfl_status`, `league`, `liveScoring`, `nfl_sched_W` and record JSON fixtures during a live Sunday.
2. `EventDiffer` + tests against fixtures.
3. `Announcer` with `AVSpeechSynthesizer`, plus settings.
4. SwiftUI matchups and NFL games views, plus the menu-bar extra.
5. ESPN `PlayFeed` (Tier B) and ID mapping.
6. Polish: notifications, event log, voices, team chimes.
