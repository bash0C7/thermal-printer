import Foundation
import Testing
@testable import ThermalPrinterCore

@Test(arguments: CardFixture.names)
func cardJSONBecomesTheSameStripTheAppComposes(name: String) throws {
    let json = try CardFixture.data(name)
    let card = try CardFixture.card(name)
    let composer = StripComposer()
    #expect(try composer.bitmap(cardJSON: json) == composer.compose([.card(card)]).bitmap)
}

@Test func cardJSONStripIs384DotsWideAndEndsWithTheFeed() throws {
    let bitmap = try StripComposer().bitmap(cardJSON: CardFixture.data("github"))
    #expect(bitmap.width == 384)
    let tail = PixelRect(x: 0, y: bitmap.height - StripComposer.defaultFeedRows, width: Bitmap1.width, height: StripComposer.defaultFeedRows)
    #expect(bitmap.blackPixels(in: tail).isEmpty)
}

@Test func malformedCardJSONIsRejected() {
    #expect(throws: DecodingError.self) { try StripComposer().bitmap(cardJSON: Data("{\"version\":1}".utf8)) }
}
