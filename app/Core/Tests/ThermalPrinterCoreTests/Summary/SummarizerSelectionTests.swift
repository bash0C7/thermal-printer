import Testing
@testable import ThermalPrinterCore

private actor CountingSummarizer: Summarizer {
    private(set) var calls = 0
    private let usedModel: Bool

    init(usedModel: Bool) {
        self.usedModel = usedModel
    }

    func summarize(_ text: String, kind: SummaryKind) async -> Summary {
        calls += 1
        return Summary(text: "要約\(calls)", usedModel: usedModel)
    }
}

@Test func unavailableModelFallsBackToTruncation() async {
    let s = await SummarizerSelector(modelAvailable: false).summarizer.summarize(String(repeating: "a", count: 100), kind: .comment)
    #expect(s.usedModel == false)
    #expect(s.text == String(repeating: "a", count: 40) + "…")
}

@Test func availableModelSelectsTheFoundationModelSummarizer() {
    #expect(SummarizerSelector(modelAvailable: true).summarizer is FoundationModelSummarizer)
}

@Test func unavailableModelSelectsTheTruncatingSummarizer() {
    #expect(SummarizerSelector(modelAvailable: false).summarizer is TruncatingSummarizer)
}

@Test func selectorWithoutArgumentFollowsTheRealAvailability() {
    let selector = SummarizerSelector()
    #expect((selector.summarizer is FoundationModelSummarizer) == FoundationModelSummarizer.isAvailable)
}

@Test func cacheReturnsTheModelSummaryForTheSameBodyWithoutCallingAgain() async {
    let base = CountingSummarizer(usedModel: true)
    let cached = CachingSummarizer(base: base, cache: SummaryCache())
    let first = await cached.summarize("同じ本文", kind: .overview)
    let second = await cached.summarize("同じ本文", kind: .overview)
    #expect(first == second)
    #expect(await base.calls == 1)
}

@Test func cacheKeepsOverviewAndCommentOfTheSameBodySeparate() async {
    let base = CountingSummarizer(usedModel: true)
    let cached = CachingSummarizer(base: base, cache: SummaryCache())
    _ = await cached.summarize("同じ本文", kind: .overview)
    _ = await cached.summarize("同じ本文", kind: .comment)
    #expect(await base.calls == 2)
}

@Test func cacheCallsAgainForADifferentBody() async {
    let base = CountingSummarizer(usedModel: true)
    let cached = CachingSummarizer(base: base, cache: SummaryCache())
    _ = await cached.summarize("本文A", kind: .overview)
    _ = await cached.summarize("本文B", kind: .overview)
    #expect(await base.calls == 2)
}

@Test func truncationResultsAreNotCachedSoTheModelIsTriedAgain() async {
    let base = CountingSummarizer(usedModel: false)
    let cached = CachingSummarizer(base: base, cache: SummaryCache())
    _ = await cached.summarize("同じ本文", kind: .overview)
    _ = await cached.summarize("同じ本文", kind: .overview)
    #expect(await base.calls == 2)
}

@Test func cacheKeyIsTheBodyHashNotTheBody() async {
    let cache = SummaryCache()
    let body = String(repeating: "長", count: 10_000)
    await cache.store(Summary(text: "x", usedModel: true), body: body, kind: .overview)
    #expect(await cache.summary(body: body, kind: .overview)?.text == "x")
    #expect(await cache.summary(body: body + "。", kind: .overview) == nil)
    #expect(SummaryCache.key(body: body, kind: .overview).count < 100)
}
