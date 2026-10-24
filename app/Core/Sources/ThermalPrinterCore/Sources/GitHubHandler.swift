import Foundation

public struct GitHubHandler: URLHandler {
    static let jsonFields = "title,body,state,updatedAt,comments,url"
    static let bodyCharacterLimit = 4000
    static let commentCharacterLimit = 2000
    static let fallbackNote = "要約モデルを使えないため、本文の先頭を切り詰めています"
    static let reasonLimit = 80

    struct Target {
        enum Kind: String {
            case issue = "issues"
            case pull = "pull"
        }

        let kind: Kind
        let owner: String
        let repo: String
        let number: Int

        var repository: String { "\(owner)/\(repo)" }
        var canonicalURL: String { "https://github.com/\(repository)/\(kind.rawValue)/\(number)" }

        var arguments: [String] {
            [kind == .issue ? "issue" : "pr", "view", String(number), "-R", repository,
             "--json", GitHubHandler.jsonFields]
        }
    }

    struct Item: Decodable {
        struct Comment: Decodable {
            let body: String?
            let createdAt: String
        }

        let title: String
        let state: String
        let updatedAt: String
        let body: String?
        let comments: [Comment]
    }

    private let runner: any ProcessRunner
    private let summarizer: any Summarizer
    private let locator: GHLocator
    private let now: @Sendable () -> Date

    public init(
        runner: any ProcessRunner,
        summarizer: any Summarizer,
        locator: GHLocator = GHLocator(),
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.runner = runner
        self.summarizer = summarizer
        self.locator = locator
        self.now = now
    }

    public func handles(_ url: URL) -> Bool {
        Self.target(of: url) != nil
    }

    public func card(for url: URL) async throws -> Card {
        guard let target = Self.target(of: url) else { throw URLHandlerError.unsupported(url) }
        guard let gh = locator.locate() else { return Self.fallback(url, reason: "gh が見つかりません") }

        let outcome: ProcessOutcome
        do {
            outcome = try await runner.run(executable: gh, arguments: target.arguments)
        } catch {
            return Self.fallback(url, reason: error.localizedDescription)
        }
        guard outcome.terminationStatus == 0 else {
            return Self.fallback(url, reason: Self.firstLine(of: outcome.output))
        }

        guard !outcome.truncated else { return Self.fallback(url, reason: "gh の出力が大きすぎます") }

        let item: Item
        do {
            item = try JSONDecoder().decode(Item.self, from: Data(outcome.output.utf8))
        } catch is DecodingError {
            return Self.fallback(url, reason: "gh の応答を読めません")
        }
        return await build(target, item)
    }

    private func build(_ target: Target, _ item: Item) async -> Card {
        let now = now()
        let formatter = ISO8601DateFormatter()
        let updated = formatter.date(from: item.updatedAt).map { "更新 \(RelativeDate.text(from: $0, now: now))" }
        let status = ([item.state.lowercased()] + [updated].compactMap { $0 }).joined(separator: " ・ ")

        let latest = item.comments.last
        async let overview = summarize(item.body, kind: .overview, limit: Self.bodyCharacterLimit)
        async let comment = summarize(latest?.body, kind: .comment, limit: Self.commentCharacterLimit)
        let summaries = await (overview, comment)

        var sections: [Card.Section] = []
        if let overview = summaries.0 {
            sections.append(Card.Section(text: overview.text))
        }
        if let comment = summaries.1, let latest {
            let age = formatter.date(from: latest.createdAt).map { "\(RelativeDate.text(from: $0, now: now)): " } ?? ""
            sections.append(Card.Section(label: "最新コメント", text: age + comment.text))
        }
        let truncated = [summaries.0, summaries.1].contains { $0?.usedModel == false }

        return Card(
            kind: .github, url: target.canonicalURL,
            header: Card.Header(lines: [target.repository], emphasis: "#\(target.number)", sublines: [status]),
            title: item.title, sections: sections,
            note: truncated ? Self.fallbackNote : nil)
    }

    private func summarize(_ text: String?, kind: SummaryKind, limit: Int) async -> Summary? {
        guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let summary = await summarizer.summarize(String(text.prefix(limit)), kind: kind)
        return summary.text.isEmpty ? nil : summary
    }

    private static func fallback(_ url: URL, reason: String) -> Card {
        let detail = reason.isEmpty ? "" : "（\(reason.prefix(reasonLimit))）"
        return UnknownURLHandler.make(for: url, note: "GitHub の内容を取得できません\(detail)")
    }

    private static func firstLine(of output: String) -> String {
        output
            .split(whereSeparator: \.isNewline)
            .first { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
    }

    static func target(of url: URL) -> Target? {
        guard url.scheme == "https", let host = url.host(percentEncoded: false),
              host == "github.com" || host == "www.github.com"
        else { return nil }
        let parts = url.pathComponents.dropFirst()
        guard parts.count >= 4, let kind = Target.Kind(rawValue: parts[parts.startIndex + 2]) else { return nil }
        let owner = parts[parts.startIndex]
        let repo = parts[parts.startIndex + 1]
        let digits = parts[parts.startIndex + 3]
        guard isOwner(owner), isRepo(repo), digits.allSatisfy({ $0.isASCII && $0.isNumber }),
              let number = Int(digits)
        else { return nil }
        return Target(kind: kind, owner: owner, repo: repo, number: number)
    }

    private static func isOwner(_ name: String) -> Bool {
        guard let first = name.first, first.isASCII, first.isLetter || first.isNumber else { return false }
        return name.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }
    }

    private static func isRepo(_ name: String) -> Bool {
        guard let first = name.first, first != "-", name != ".", name != ".." else { return false }
        return name.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" || $0 == ".") }
    }
}
