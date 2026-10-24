import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import ThermalPrinterCore

private let printable = (Bitmap1.contentLeft + 8)..<(Bitmap1.contentLeft + Bitmap1.contentWidth - 8)

private extension Bitmap1 {
    func contentColumns() -> Bitmap1 {
        crop(PixelRect(x: Bitmap1.contentLeft, y: 0, width: Bitmap1.contentWidth, height: height))
    }
}

private func stripCard(_ name: String) throws -> Card {
    let url = printerRepoRoot.appending(path: "test/fixtures/cards/\(name).json")
    return try JSONDecoder().decode(Card.self, from: Data(contentsOf: url))
}

private func samplePNG() throws -> Data {
    let data = NSMutableData()
    let destination = try #require(CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil))
    CGImageDestinationAddImage(destination, ImageLoader.sampleImage(), nil)
    try #require(CGImageDestinationFinalize(destination))
    return data as Data
}

private func blackCount(_ bitmap: Bitmap1, row: Int, columns: Range<Int>) -> Int {
    bitmap.blackPixels(in: PixelRect(x: columns.lowerBound, y: row, width: columns.count, height: 1)).count
}

@Test func partsAreSeparatedByADashedCutLine() {
    let strip = StripComposer(feedRows: 0, topRows: 0).compose([.text("a"), .text("b")])
    #expect(strip.cutLineRows.count == 1)
    let row = strip.cutLineRows[0]
    let black = blackCount(strip.bitmap, row: row, columns: 0..<Bitmap1.width)
    #expect(black > 0)
    #expect(black < printable.count)
    #expect(blackCount(strip.bitmap, row: row, columns: printable) == black)
    #expect(blackCount(strip.bitmap, row: row, columns: (Bitmap1.contentLeft + 8)..<(Bitmap1.contentLeft + 16)) == 8)
    #expect(blackCount(strip.bitmap, row: row, columns: (Bitmap1.contentLeft + 16)..<(Bitmap1.contentLeft + 24)) == 0)
}

@Test func cutLineCountIsPartsMinusOne() {
    let composer = StripComposer(feedRows: 0, topRows: 0)
    #expect(composer.compose([.text("a")]).cutLineRows.isEmpty)
    #expect(composer.compose([.text("a"), .text("b"), .text("c")]).cutLineRows.count == 2)
}

@Test func trailingFeedIsAppendedAsWhiteRows() {
    let a = StripComposer(feedRows: 0, topRows: 0).compose([.text("a")]).bitmap
    let b = StripComposer(feedRows: 80, topRows: 0).compose([.text("a")]).bitmap
    #expect(b.height - a.height == 80)
    let tail = PixelRect(x: 0, y: a.height, width: Bitmap1.width, height: 80)
    #expect(b.blackPixels(in: tail).isEmpty)
}

@Test func topRowsAreWhiteAndPushTheContentDown() {
    let a = StripComposer(feedRows: 0, topRows: 0).compose([.text("a")]).bitmap
    let b = StripComposer(feedRows: 0, topRows: 24).compose([.text("a")]).bitmap
    #expect(b.height - a.height == 24)
    #expect(b.blackPixels(in: PixelRect(x: 0, y: 0, width: Bitmap1.width, height: 24)).isEmpty)
    #expect(b.crop(PixelRect(x: 0, y: 24, width: Bitmap1.width, height: a.height)) == a)
}

@Test func defaultComposerFeedsPastTheTearBar() {
    let defaults = StripComposer()
    #expect(defaults.feedRows == StripComposer.defaultFeedRows)
    #expect(defaults.feedRows > 0)
    #expect(defaults.topRows == StripComposer.defaultTopRows)
}

@Test func emptyPartListGivesAnEmptyStripWithoutFeed() {
    let strip = StripComposer().compose([])
    #expect(strip.bitmap.height == 0)
    #expect(strip.cutLineRows.isEmpty)
    #expect(strip.partRanges.isEmpty)
}

@Test func stripHeightIsPartsPlusSeparatorsPlusFeed() {
    let composer = StripComposer(feedRows: 40, topRows: 8, gapRows: 10)
    let a = TextRenderer(margin: 8).render("a", style: TextStyle.body).height
    let b = TextRenderer(margin: 8).render("b", style: TextStyle.body).height
    let strip = composer.compose([.text("a"), .text("b")])
    #expect(strip.bitmap.height == 8 + a + (10 + 1 + 10) + b + 40)
    #expect(strip.partRanges == [8..<(8 + a), (8 + a + 21)..<(8 + a + 21 + b)])
    #expect(strip.cutLineRows == [8 + a + 10])
}

@Test func eachPartIsDrawnWhereItsRangeSays() throws {
    let composer = StripComposer(feedRows: 0, topRows: 0)
    let card = try stripCard("github")
    let strip = composer.compose([.text("a"), .card(card)])
    let expected = try CardRenderer(margin: 8).render(card).bitmap
    let range = strip.partRanges[1]
    #expect(range.count == expected.height)
    #expect(strip.bitmap.crop(PixelRect(x: Bitmap1.contentLeft, y: range.lowerBound, width: Bitmap1.contentWidth, height: range.count)) == expected)
}

@Test func textSizeChangesTheRenderedHeight() {
    let composer = StripComposer(feedRows: 0, topRows: 0)
    let small = composer.compose([.text("あいう", size: .small)]).bitmap.height
    let large = composer.compose([.text("あいう", size: .large)]).bitmap.height
    #expect(small < large)
}

@Test func markdownPartRendersWithMarkdownStyleUnlessPlainTextIsChosen() {
    let composer = StripComposer(feedRows: 0, topRows: 0)
    let styled = composer.compose([.markdown("# 見出し")]).bitmap
    let plain = composer.compose([.markdown("# 見出し", asPlainText: true)]).bitmap
    #expect(styled != plain)
    #expect(styled.contentColumns() == MarkdownRenderer(margin: 8).render("# 見出し"))
}

@Test func morningCardsMeetingMemoAndPhotoComposeIntoOneStrip() throws {
    let memo = try String(contentsOf: printerRepoRoot.appending(path: "test/fixtures/meeting-memo.md"), encoding: .utf8)
    let parts: [Part] = try ["github", "slack", "url", "reminder"].map { .card(try stripCard($0)) }
    let strip = StripComposer().compose(parts + [.markdown(memo), .image(try samplePNG())])
    #expect(strip.failures.isEmpty)
    #expect(strip.cutLineRows.count == 5)
    #expect(strip.partRanges.count == 6)
    #expect(strip.partRanges.last!.upperBound + StripComposer.defaultFeedRows == strip.bitmap.height)
}

@Test(arguments: [0, 1, 2, 3])
func inkOfTextualPartsStaysInsideThePrintableWidth(which: Int) throws {
    let long = String(repeating: "とても長い文、https://example.com/very/long/path/ ", count: 12)
    let parts: [[Part]] = [
        [.text(long, size: .large)],
        [.markdown("# " + long + "\n- " + long + "\n```\n" + long + "\n```")],
        [.card(try stripCard("slack")), .card(try stripCard("reminder"))],
        [.text("a"), .markdown(long), .text("b")],
    ]
    let strip = StripComposer().compose(parts[which])
    #expect(strip.bitmap.blackPixels(inColumns: 0..<printable.lowerBound).isEmpty)
    #expect(strip.bitmap.blackPixels(inColumns: printable.upperBound..<Bitmap1.width).isEmpty)
}

@Test func imagePartIsLoadedWithItsPhotoSettings() throws {
    let png = try samplePNG()
    let composer = StripComposer(feedRows: 0, topRows: 0)
    let neutral = composer.compose([.image(png)])
    #expect(neutral.bitmap.contentColumns() == (try ImageLoader.bitmap(from: png)))

    let settings = PhotoSettings(brightness: 10, contrast: 1.3, gamma: 0.8, rotation: .degrees90)
    let adjusted = composer.compose([.image(png, settings)])
    let expected = try ImageLoader.bitmap(
        from: png, adjust: PhotoAdjust(brightness: 10, contrast: 1.3, gamma: 0.8), rotation: .degrees90
    )
    #expect(adjusted.bitmap.contentColumns() == expected)
    #expect(adjusted.bitmap.height != neutral.bitmap.height)
}

@Test func brightestSettingGivesAWhitePhoto() throws {
    let settings = PhotoSettings(brightness: 255, contrast: 1, gamma: 1)
    let strip = StripComposer(feedRows: 0, topRows: 0).compose([.image(try samplePNG(), settings)])
    #expect(strip.bitmap.blackPixels(inColumns: 0..<Bitmap1.width).isEmpty)
}

@Test func unreadablePartsLeaveAPlaceholderAndAFailureRecord() {
    let composer = StripComposer(feedRows: 0, topRows: 0)
    let strip = composer.compose([.text("a"), .image(Data([1, 2, 3])), .text("b")])
    #expect(strip.failures.map(\.partIndex) == [1])
    #expect(!strip.failures[0].message.isEmpty)
    #expect(strip.partRanges.count == 3)
    #expect(strip.partRanges[1].count > 0)
    #expect(!strip.bitmap.blackPixels(in: PixelRect(x: 0, y: strip.partRanges[1].lowerBound, width: 384, height: strip.partRanges[1].count)).isEmpty)
}

@Test func unprintableCardLeavesAFailureRecord() {
    let card = Card(
        kind: .url, url: "https://example.com/" + String(repeating: "a", count: 4000),
        header: Card.Header(lines: ["x"]), title: "t"
    )
    let strip = StripComposer(feedRows: 0, topRows: 0).compose([.card(card)])
    #expect(strip.failures.map(\.partIndex) == [0])
    #expect(strip.bitmap.height > 0)
}

@Test func lengthPolicyJudgesTheComposedStrip() throws {
    let strip = StripComposer().compose([.text(String(repeating: "長い文章。", count: 400))])
    let policy = LengthPolicy(thresholdCentimeters: 30)
    #expect(policy.isTooLong(strip.bitmap) == (strip.bitmap.height > 2400))
    #expect(strip.bitmap.height > 2400)
}

private func solidBlackPNG() -> Data {
    let context = makeRGBAContext(width: 120, height: 60)
    context.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: 120, height: 60))
    return encode(context.makeImage()!, as: .png)
}

@Test func noPartKindPutsInkOutsideTheContentColumns() throws {
    let long = String(repeating: "とても長い文、https://example.com/very/long/path/ ", count: 12)
    let parts: [Part] = [
        .text(long, size: .large),
        .markdown("# " + long + "\n- " + long + "\n---\n> " + long),
        .card(try stripCard("github")),
        .card(try stripCard("slack")),
        .image(solidBlackPNG()),
    ]
    let strip = StripComposer().compose(parts)
    let contentRight = Bitmap1.contentLeft + Bitmap1.contentWidth
    #expect(strip.failures.isEmpty)
    #expect(strip.bitmap.blackPixels(inColumns: 0..<Bitmap1.contentLeft).isEmpty)
    #expect(strip.bitmap.blackPixels(inColumns: contentRight..<Bitmap1.width).isEmpty)
    let photo = strip.partRanges[4]
    let photoRect = PixelRect(x: Bitmap1.contentLeft, y: photo.lowerBound, width: Bitmap1.contentWidth, height: photo.count)
    #expect(strip.bitmap.blackPixels(in: photoRect).count == Bitmap1.contentWidth * photo.count)
    #expect(strip.bitmap.blackPixels(in: PixelRect(x: 0, y: photo.lowerBound, width: Bitmap1.width, height: photo.count)).count == Bitmap1.contentWidth * photo.count)
}

@Test func partsAreDrawnFromContentLeft() {
    let rendered = TextRenderer(margin: 8).render("あいう", style: .body)
    let strip = StripComposer(feedRows: 0, topRows: 0).compose([.text("あいう")]).bitmap
    let shifted = strip.crop(PixelRect(x: Bitmap1.contentLeft, y: 0, width: Bitmap1.contentWidth, height: rendered.height))
    #expect(shifted == rendered)
    #expect(!rendered.blackPixels(inColumns: 0..<Bitmap1.contentWidth).isEmpty)
}

@Test func cutLineIsShiftedByContentLeftAndStopsAtTheContentWidthMinusTheMargin() {
    let strip = StripComposer(feedRows: 0, topRows: 0).compose([.text("a"), .text("b")])
    let row = strip.cutLineRows[0]
    let ink = strip.bitmap.blackPixels(in: PixelRect(x: 0, y: row, width: Bitmap1.width, height: 1)).map(\.x)
    #expect(ink.min() == Bitmap1.contentLeft + 8)
    #expect(ink.max()! < Bitmap1.contentLeft + Bitmap1.contentWidth - 8)
}
