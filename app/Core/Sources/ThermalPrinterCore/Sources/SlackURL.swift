import Foundation

public struct SlackURL: Equatable, Sendable {
    private static let domainSuffix = ".slack.com"
    private static let weekdays = ["日", "月", "火", "水", "木", "金", "土"]

    public let urlString: String
    public let workspace: String
    public let channelID: String
    public let seconds: Int
    public let microseconds: Int

    public init?(_ string: String) {
        guard let components = URLComponents(string: string),
              components.scheme == "https",
              let host = components.host, host.hasSuffix(Self.domainSuffix)
        else { return nil }
        let workspace = String(host.dropLast(Self.domainSuffix.count))
        let parts = components.path.split(separator: "/", omittingEmptySubsequences: true)
        guard Self.isWorkspaceName(workspace),
              parts.count == 3, parts[0] == "archives",
              Self.isChannelID(parts[1]),
              let stamp = Self.splitStamp(parts[2])
        else { return nil }
        self.urlString = string
        self.workspace = workspace
        self.channelID = String(parts[1])
        self.seconds = stamp.seconds
        self.microseconds = stamp.microseconds
    }

    public var jstText: String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        let at = calendar.dateComponents(
            [.year, .month, .day, .weekday, .hour, .minute],
            from: Date(timeIntervalSince1970: TimeInterval(seconds)))
        let date = "\(at.year!)/\(Self.twoDigits(at.month!))/\(Self.twoDigits(at.day!))"
        let time = "\(Self.twoDigits(at.hour!)):\(Self.twoDigits(at.minute!))"
        return "\(date)(\(Self.weekdays[at.weekday! - 1])) \(time)"
    }

    public func card() -> Card {
        Card(
            kind: .slack, url: urlString,
            header: Card.Header(lines: [workspace], emphasis: "#\(channelID)", sublines: [jstText]),
            title: "Slack のメッセージ")
    }

    private static func twoDigits(_ value: Int) -> String {
        value < 10 ? "0\(value)" : "\(value)"
    }

    private static func isWorkspaceName(_ name: String) -> Bool {
        !name.isEmpty && name.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }
    }

    private static func isChannelID(_ part: Substring) -> Bool {
        guard let first = part.first, "CDG".contains(first), part.count >= 2 else { return false }
        return part.allSatisfy { $0.isASCII && ($0.isNumber || $0.isUppercase) }
    }

    private static func splitStamp(_ part: Substring) -> (seconds: Int, microseconds: Int)? {
        guard part.first == "p" else { return nil }
        let digits = part.dropFirst()
        guard digits.count == 16, digits.allSatisfy({ $0.isASCII && $0.isNumber }),
              let seconds = Int(digits.prefix(10)), let microseconds = Int(digits.suffix(6))
        else { return nil }
        return (seconds, microseconds)
    }
}

public struct SlackURLHandler: URLHandler {
    public init() {}

    public func handles(_ url: URL) -> Bool {
        SlackURL(url.absoluteString) != nil
    }

    public func card(for url: URL) async throws -> Card {
        guard let slack = SlackURL(url.absoluteString) else { throw URLHandlerError.unsupported(url) }
        return slack.card()
    }
}
