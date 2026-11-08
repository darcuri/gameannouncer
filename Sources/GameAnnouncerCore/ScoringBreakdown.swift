import Foundation

/// Fantasy points by scoring category ("159 Passing Yards: 7.95 pts") for every player with
/// stats this week, using the league's own rules.
///
/// No MFL export has this, so it comes from the league's live scoring web page, which puts
/// each player's breakdown in the title of their points cell:
/// `id="points_14777"><a … title='&bull;4.00 pts for 1 Passing TDs &#xA;&bull;7.95 pts for 159 Passing Yards &#xA;'>`.
public struct ScoringBreakdowns: Sendable {
    public struct Line: Sendable, Equatable {
        /// MFL's wording, such as "Passing Yards" or "Total Points Allowed".
        public let category: String
        /// The stat as MFL shows it, such as "159".
        public let count: String
        public let points: Double

        public init(category: String, count: String, points: Double) {
            self.category = category
            self.count = count
            self.points = points
        }
    }

    public let byPlayer: [String: [Line]]

    public init(byPlayer: [String: [Line]]) { self.byPlayer = byPlayer }

    public subscript(playerID: String) -> [Line] { byPlayer[playerID] ?? [] }

    private static let cell = try! NSRegularExpression(
        pattern: #"id="points_([^"]+)"[^>]*>\s*<a\b[^>]*?\btitle=(['"])(.*?)\2"#,
        options: [.dotMatchesLineSeparators])

    private static let line = try! NSRegularExpression(
        pattern: #"^(-?[0-9.]+)\s+pts?\s+for\s+(-?[0-9.]+)\s+(.+?)\s*$"#,
        options: [.dotMatchesLineSeparators])

    /// Parses MFL's `live_scoring_summary` page. Players appear once per matchup they're in;
    /// the first breakdown wins.
    public init(liveScoringPage html: String) {
        var result: [String: [Line]] = [:]
        let ns = html as NSString
        for match in Self.cell.matches(in: html, range: NSRange(location: 0, length: ns.length)) {
            let id = ns.substring(with: match.range(at: 1))
            guard result[id] == nil else { continue }
            let title = Self.decodeEntities(ns.substring(with: match.range(at: 3)))
            let lines = title.split(separator: "•").compactMap { Self.parseLine(String($0)) }
            if !lines.isEmpty { result[id] = lines }
        }
        byPlayer = result
    }

    private static func parseLine(_ text: String) -> Line? {
        let text = text.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespaces)
        let ns = text as NSString
        guard let m = line.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)),
              let points = Double(ns.substring(with: m.range(at: 1))) else { return nil }
        let category = ns.substring(with: m.range(at: 3))
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return Line(category: category, count: ns.substring(with: m.range(at: 2)), points: points)
    }

    private static let named = ["bull": "•", "amp": "&", "quot": "\"", "apos": "'", "lt": "<", "gt": ">", "nbsp": " "]

    private static func decodeEntities(_ s: String) -> String {
        var out = ""
        var rest = Substring(s)
        while let amp = rest.firstIndex(of: "&") {
            out += rest[..<amp]
            let after = rest[rest.index(after: amp)...]
            guard let semi = after.prefix(10).firstIndex(of: ";") else {
                out += "&"
                rest = after
                continue
            }
            let name = after[..<semi]
            var decoded: String?
            if name.hasPrefix("#x") || name.hasPrefix("#X") {
                decoded = UInt32(name.dropFirst(2), radix: 16).flatMap(Unicode.Scalar.init).map { String($0) }
            } else if name.hasPrefix("#") {
                decoded = UInt32(name.dropFirst()).flatMap(Unicode.Scalar.init).map { String($0) }
            } else {
                decoded = named[String(name)]
            }
            if let decoded {
                out += decoded
                rest = after[after.index(after: semi)...]
            } else {
                out += "&"
                rest = after
            }
        }
        return out + rest
    }
}
