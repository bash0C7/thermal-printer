import Foundation
import Testing
@testable import ThermalPrinterCore

private struct KindSummarizer: Summarizer {
    func summarize(_ text: String, kind: SummaryKind) async -> Summary {
        switch kind {
        case .heading: Summary(text: "見出し", usedModel: true)
        case .digest: Summary(text: "要約\nです", usedModel: true)
        default: Summary(text: text, usedModel: true)
        }
    }
}

private let original = "会議の議題は三つ。印字長の警告、要約の品質、QRコードに収める文章量。それぞれ担当を決めて、来週までに結果を持ち寄る。"

@Test func memoCardCarriesHeadingDigestAndTheCharacterCount() async {
    let card = await MemoCard.make(original, summarizer: KindSummarizer())
    #expect(card.kind == .memo)
    #expect(card.url == nil)
    #expect(card.title == "見出し")
    #expect(card.sections == [Card.Section(text: "要約\nです")])
    #expect(card.header.lines == ["メモ"])
    #expect(card.header.sublines == ["\(original.count)文字"])
    #expect(card.note == nil)
}

@Test func memoQRHoldsTheOriginalText() async throws {
    let card = await MemoCard.make(original, summarizer: KindSummarizer())
    let qr = try #require(card.qr)
    #expect(qr == original)
}

@Test func memoCardRendersWithItsQRAndScansBackToTheOriginal() async throws {
    let card = await MemoCard.make(original, summarizer: KindSummarizer())
    let rendered = try CardRenderer().render(card)
    let frame = try #require(rendered.qrFrame)
    var qrOnly = Bitmap1(height: frame.height)
    for y in 0..<frame.height {
        for x in 0..<frame.width where rendered.bitmap[x: frame.minX + x, y: frame.minY + y] {
            qrOnly.set(x: x, y: y)
        }
    }
    #expect(try QRDecoder.decode(qrOnly) == original)
}

@Test func memoWithTruncationFallbackIsNoted() async {
    let card = await MemoCard.make(original, summarizer: TruncatingSummarizer())
    #expect(card.note == GitHubHandler.fallbackNote)
}

@Test func memoTooLongForTheQRSaysHowMuchWasStored() async throws {
    var state: UInt64 = 7
    let pool = Array("あいうえおかきくけこさしすせそたちつてとなにぬねのはひふへほまみむめもやゆよらりるれろわをん日本語感熱印字紙幅白黒")
    let long = String((0..<3000).map { _ in
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return pool[Int(state >> 33) % pool.count]
    })
    let card = await MemoCard.make(long, summarizer: KindSummarizer())
    let packed = QRPayload.pack(long)
    #expect(card.note == "QRには全3000文字のうち先頭\(packed.packedCharacters)文字を収めています")
    #expect(card.qr == String(long.prefix(packed.packedCharacters)))
    _ = try CardRenderer().render(card)
}

@Test func memoCardEncodesQRAndRoundTrips() async throws {
    let card = await MemoCard.make(original, summarizer: KindSummarizer())
    let decoded = try JSONDecoder().decode(Card.self, from: JSONEncoder().encode(card))
    #expect(decoded == card)
}

@Test func imageTokensAreReplacedByMarkdownImages() {
    let text = "前\n[Image #1]\n後 [Image #2] [Image #9]"
    let markdown = Draft.markdown(text, images: [1: URL(fileURLWithPath: "/tmp/a/image-1.png"), 2: URL(fileURLWithPath: "/tmp/a/image-2.png")])
    #expect(markdown == "前\n\n\n![](file:///tmp/a/image-1.png)\n\n\n後 \n\n![](file:///tmp/a/image-2.png)\n\n [Image #9]")
}

@Test func plainTextDropsEveryImageToken() {
    #expect(Draft.plainText("前[Image #1]後\n[Image #20]") == "前後\n")
}

@Test func tokenTextIsStable() {
    #expect(Draft.token(3) == "[Image #3]")
}

private func scratchDraft() -> DraftDocument {
    DraftDocument(directory: FileManager.default.temporaryDirectory.appending(path: "draft-test-\(UUID().uuidString)"))
}

@Test func blankDraftHasNoPartsAndCannotBeDigested() {
    var draft = scratchDraft()
    draft.edit("  \n")
    #expect(draft.parts.isEmpty)
    #expect(!draft.canDigest)
    draft.edit("[Image #1]")
    #expect(!draft.canDigest)
}

@Test func draftImagesGetNextNumbersAndAppearAsMarkdownImages() throws {
    var draft = scratchDraft()
    #expect(try draft.addImage(Data([1])) == "[Image #1]")
    #expect(try draft.addImage(Data([2])) == "[Image #2]")
    draft.edit("a [Image #2]")
    guard case .markdown(let markdown, _, _) = try #require(draft.parts.first) else {
        Issue.record("not markdown")
        return
    }
    #expect(markdown.contains("![](file://"))
    #expect(markdown.contains("image-2.png"))
    draft.clear()
    #expect(try draft.addImage(Data([3])) == "[Image #1]")
}

@Test func digestReplacesTheMarkdownUntilTheTextChanges() async {
    var draft = scratchDraft()
    draft.edit("本文")
    let card = await MemoCard.make("本文", summarizer: KindSummarizer())
    draft.apply(card, to: "別の本文")
    #expect(draft.digest == nil)
    draft.apply(card, to: "本文")
    #expect(draft.parts == [.card(card)])
    draft.edit("本文を直した")
    #expect(draft.digest == nil)
}
