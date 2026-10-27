import Foundation

public enum HTMLText {
    public struct Page: Equatable, Sendable {
        public let title: String?
        public let body: String
    }

    private static let title = try! NSRegularExpression(pattern: "<title[^>]*>(.*?)</title>", options: [.caseInsensitive, .dotMatchesLineSeparators])
    private static let hiddenBlocks = try! NSRegularExpression(
        pattern: "<(script|style|noscript|svg|head|template)\\b[^>]*>.*?</\\1\\s*>|<!--.*?-->",
        options: [.caseInsensitive, .dotMatchesLineSeparators])
    private static let blockTags = try! NSRegularExpression(
        pattern: "</?(p|div|br|li|ul|ol|tr|table|section|article|header|footer|h[1-6]|pre|blockquote)\\b[^>]*>",
        options: [.caseInsensitive])
    private static let anyTag = try! NSRegularExpression(pattern: "<[^>]*>")
    private static let entity = try! NSRegularExpression(pattern: "&(#x[0-9a-fA-F]+|#[0-9]+|[a-zA-Z]+);")
    private static let named: [String: String] = [
        "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": " ",
    ]

    public static func extract(_ html: String) -> Page {
        let pageTitle = firstGroup(of: title, in: html).map { collapse(decode(strip($0))) }.flatMap { $0.isEmpty ? nil : $0 }
        let visible = replace(hiddenBlocks, in: html, with: " ")
        let broken = replace(blockTags, in: visible, with: "\n")
        let body = decode(replace(anyTag, in: broken, with: ""))
            .split(whereSeparator: \.isNewline)
            .map { collapse(String($0)) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
        return Page(title: pageTitle, body: body)
    }

    private static func strip(_ text: String) -> String {
        replace(anyTag, in: text, with: "")
    }

    private static func collapse(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    private static func replace(_ regex: NSRegularExpression, in text: String, with template: String) -> String {
        regex.stringByReplacingMatches(
            in: text, range: NSRange(text.startIndex..., in: text), withTemplate: template)
    }

    private static func firstGroup(of regex: NSRegularExpression, in text: String) -> String? {
        guard let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
            let range = Range(match.range(at: 1), in: text)
        else { return nil }
        return String(text[range])
    }

    private static func decode(_ text: String) -> String {
        var result = ""
        var cursor = text.startIndex
        for match in entity.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            guard let whole = Range(match.range, in: text), let name = Range(match.range(at: 1), in: text) else { continue }
            result += text[cursor..<whole.lowerBound]
            result += replacement(for: String(text[name])) ?? String(text[whole])
            cursor = whole.upperBound
        }
        return result + text[cursor...]
    }

    private static func replacement(for name: String) -> String? {
        if name.hasPrefix("#x") || name.hasPrefix("#X") {
            return UInt32(name.dropFirst(2), radix: 16).flatMap(Unicode.Scalar.init).map(String.init)
        }
        if name.hasPrefix("#") {
            return UInt32(name.dropFirst()).flatMap(Unicode.Scalar.init).map(String.init)
        }
        return named[name]
    }
}

public struct WebPageHandler: URLHandler {
    public static let curl = URL(fileURLWithPath: "/usr/bin/curl")
    static let minimumBodyCharacters = 20
    static let reasonLimit = 80

    public enum Failure: Error, LocalizedError, Equatable {
        case fetchFailed(String)
        case noText

        public var errorDescription: String? {
            switch self {
            case .fetchFailed(let reason): reason.isEmpty ? "curl が失敗しました" : reason
            case .noText: "本文を取り出せません"
            }
        }
    }

    private let runner: any ProcessRunner
    private let summarizer: any Summarizer
    private let curl: URL

    public init(runner: any ProcessRunner, summarizer: any Summarizer, curl: URL = WebPageHandler.curl) {
        self.runner = runner
        self.summarizer = summarizer
        self.curl = curl
    }

    public func handles(_ url: URL) -> Bool {
        url.scheme == "http" || url.scheme == "https"
    }

    public func card(for url: URL) async throws -> Card {
        let outcome = try await runner.run(executable: curl, arguments: Self.arguments(for: url))
        guard outcome.terminationStatus == 0 else {
            throw Failure.fetchFailed(String(Self.firstLine(of: outcome.output).prefix(Self.reasonLimit)))
        }
        guard !outcome.truncated else { throw Failure.fetchFailed("ページが大きすぎます") }

        let page = HTMLText.extract(outcome.output)
        guard page.body.count >= Self.minimumBodyCharacters,
            page.body.filter({ $0 == "\u{FFFD}" }).count * 10 < page.body.count
        else { throw Failure.noText }

        let digest = await TextDigest.make(page.body, summarizer: summarizer)
        let origin = url.host(percentEncoded: false) ?? ""
        let generated = digest.heading.text
        return Card(
            kind: .url, url: url.absoluteString,
            header: Card.Header(lines: [origin]),
            title: page.title ?? (generated.isEmpty ? url.absoluteString : generated),
            sections: digest.sections,
            note: digest.usedFallback ? GitHubHandler.fallbackNote : nil)
    }

    static func arguments(for url: URL) -> [String] {
        [
            "--silent", "--show-error", "--location", "--max-time", "20", "--max-filesize", "3000000",
            "--proto", "=http,https", "--proto-redir", "=http,https",
            "--user-agent", "Mozilla/5.0 (Macintosh) ThermalPrinter", url.absoluteString,
        ]
    }

    private static func firstLine(of output: String) -> String {
        output
            .split(whereSeparator: \.isNewline)
            .first { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
    }
}
