import CryptoKit
import Foundation

public actor SummaryCache {
    private var entries: [String: Summary] = [:]

    public init() {}

    nonisolated static func key(body: String, kind: SummaryKind) -> String {
        let digest = SHA256.hash(data: Data(body.utf8)).map { String(format: "%02x", $0) }.joined()
        return "\(kind):\(digest)"
    }

    public func summary(body: String, kind: SummaryKind) -> Summary? {
        entries[Self.key(body: body, kind: kind)]
    }

    public func store(_ summary: Summary, body: String, kind: SummaryKind) {
        entries[Self.key(body: body, kind: kind)] = summary
    }
}

public struct CachingSummarizer: Summarizer {
    private let base: any Summarizer
    private let cache: SummaryCache

    public init(base: any Summarizer, cache: SummaryCache) {
        self.base = base
        self.cache = cache
    }

    public func summarize(_ text: String, kind: SummaryKind) async -> Summary {
        if let hit = await cache.summary(body: text, kind: kind) { return hit }
        let result = await base.summarize(text, kind: kind)
        if result.usedModel { await cache.store(result, body: text, kind: kind) }
        return result
    }
}
