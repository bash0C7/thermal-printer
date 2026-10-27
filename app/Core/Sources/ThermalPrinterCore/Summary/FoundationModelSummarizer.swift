import FoundationModels
import Foundation

public struct FoundationModelSummarizer: Summarizer {
    static let locale = Locale(identifier: "ja_JP")
    static let reservedTokens = 1536
    static let maxShrinkAttempts = 8

    public init() {}

    public static var unavailableReason: String? {
        let model = SystemLanguageModel.default
        if case .unavailable(let reason) = model.availability { return "unavailable(\(reason))" }
        guard model.supportsLocale(locale) else { return "unsupportedLocale(\(locale.identifier))" }
        return nil
    }

    public static var isAvailable: Bool { unavailableReason == nil }

    public func summarize(_ text: String, kind: SummaryKind) async -> Summary {
        let truncated = await TruncatingSummarizer().summarize(text, kind: kind)
        if truncated.text.isEmpty { return truncated }
        if let reason = Self.unavailableReason {
            return Summary(text: truncated.text, usedModel: false, fallbackReason: reason)
        }
        do {
            let fitted = kind.fit(try await generate(text, kind: kind))
            if fitted.isEmpty { return Summary(text: truncated.text, usedModel: false, fallbackReason: "emptyOutput") }
            return Summary(text: fitted, usedModel: true)
        } catch {
            return Summary(text: truncated.text, usedModel: false, fallbackReason: "\(error)")
        }
    }

    private func generate(_ text: String, kind: SummaryKind) async throws -> String {
        let model = SystemLanguageModel.default
        let budget = model.contextSize - Self.reservedTokens
        var body = text
        var tokens = try await model.tokenCount(for: Self.prompt(body, kind: kind))
        var attempts = 0
        while tokens > budget && attempts < Self.maxShrinkAttempts {
            let keep = max(1, body.count * budget / tokens * 9 / 10)
            body = String(body.prefix(keep))
            tokens = try await model.tokenCount(for: Self.prompt(body, kind: kind))
            attempts += 1
        }
        let session = LanguageModelSession(model: model, instructions: Self.instructions(for: kind))
        return try await session.respond(to: Self.prompt(body, kind: kind)).content
    }

    static func prompt(_ body: String, kind: SummaryKind) -> String {
        switch kind {
        case .overview: "次のGitHubの本文を要約してください。\n\n本文:\n\(body)"
        case .comment: "次のGitHubの最新コメントを要約してください。\n\nコメント:\n\(body)"
        case .heading: "次の文章に見出しを付けてください。\n\n文章:\n\(body)"
        case .digest: "次の文章を要約してください。\n\n文章:\n\(body)"
        }
    }

    static func instructions(for kind: SummaryKind) -> String {
        let common = "前置き、見出し、箇条書きの記号、Markdown、引用符は使いません。本文に無いことは書きません。"
        switch kind {
        case .overview:
            return "あなたはGitHubのissueやpull requestの本文を日本語で要約する編集者です。何についての話で、何が問題で、何が求められているかを、合計\(kind.characterLimit)文字程度、最大\(kind.lineLimit)行で書きます。\(common)"
        case .comment:
            return "あなたはGitHubの最新コメントを日本語で要約する編集者です。誰かが何を伝えているかを、合計\(kind.characterLimit)文字程度、最大\(kind.lineLimit)行で書きます。\(common)"
        case .heading:
            return "あなたは文章に見出しを付ける編集者です。内容を表す名詞句の見出しを、\(kind.characterLimit)文字以内の1行で書きます。文末に句点は付けません。\(common)"
        case .digest:
            return "あなたは文章を日本語で要約する編集者です。何についての文章で、要点が何かを、合計\(kind.characterLimit)文字程度、最大\(kind.lineLimit)行で書きます。\(common)"
        }
    }
}
