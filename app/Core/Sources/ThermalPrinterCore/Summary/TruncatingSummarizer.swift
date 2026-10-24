public struct TruncatingSummarizer: Summarizer {
    public init() {}

    public func summarize(_ text: String, kind: SummaryKind) async -> Summary {
        Summary(text: Self.truncate(text, limit: kind.characterLimit), usedModel: false)
    }

    static func truncate(_ text: String, limit: Int) -> String {
        let flat = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard flat.count > limit else { return flat }
        return String(flat.prefix(limit)) + "…"
    }
}
