import Foundation
import Testing
@testable import ThermalPrinterCore

private let japanese = """
感熱プリンターに、Macから印字する道具。Macアプリが紙幅の白黒ラスタを組み、PicoRubyのCLIがBLEで送る。印字を担うPhomemoの制御はmrbgemにある。
会議の議題は三つ。印字長の警告、要約の品質、QRコードに収める文章量。それぞれ担当を決めて、来週までに結果を持ち寄る。
"""

private func varied(characters: Int) -> String {
    var state: UInt64 = 0x9E37_79B9_7F4A_7C15
    let pool = Array("あいうえおかきくけこさしすせそたちつてとなにぬねのはひふへほまみむめもやゆよらりるれろわをんの日本語感熱印字紙幅白黒計画進捗確認議題担当結果品質")
    return String((0..<characters).map { _ in
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return pool[Int(state >> 33) % pool.count]
    })
}

@Test func shortTextIsPackedAsItIs() {
    let packed = QRPayload.pack(japanese)
    #expect(packed.isComplete)
    #expect(packed.payload == japanese)
    #expect(packed.packedCharacters == japanese.count)
    #expect(QRCode.moduleCount(for: packed.payload).map { $0 <= QRPayload.maxCardModules } == true)
}

@Test func emptyTextIsPackedAsEmpty() {
    let packed = QRPayload.pack("")
    #expect(packed.isComplete)
    #expect(packed.payload.isEmpty)
}

@Test func longTextIsCutToTheLargestPrefixThatFitsTheCard() throws {
    let text = varied(characters: 3000)
    let packed = QRPayload.pack(text)
    #expect(!packed.isComplete)
    #expect(packed.totalCharacters == 3000)
    #expect(packed.packedCharacters > 0)
    #expect(packed.payload == String(text.prefix(packed.packedCharacters)))
    let modules = try #require(QRCode.moduleCount(for: packed.payload))
    #expect(modules <= QRPayload.maxCardModules)
    let longer = String(text.prefix(packed.packedCharacters + 1))
    #expect((QRCode.moduleCount(for: longer) ?? .max) > QRPayload.maxCardModules)
}

@Test func packedPayloadFitsTheCardAndScansBackToTheOriginalText() throws {
    let packed = QRPayload.pack(varied(characters: 400))
    let qr = try QRCode(packed.payload)
    #expect(qr.dotsPerModule >= 3)
    #expect(qr.sideDots <= Bitmap1.contentWidth - 16)
    #expect(try QRDecoder.decode(qr.bitmap) == packed.payload)
}

@Test func englishFitsFarMoreCharactersThanJapanese() {
    let english = String(repeating: "The printer waits for the next card to arrive and then prints it. ", count: 60)
    let packedEnglish = QRPayload.pack(english)
    let packedJapanese = QRPayload.pack(varied(characters: 3000))
    #expect(packedEnglish.packedCharacters > packedJapanese.packedCharacters * 2)
}

@Test(arguments: ["Note: the printer is ready.", "  TODO: buy paper", "a:b", "tel:0312345678"])
func textThatLooksLikeASchemeGetsALabelLine(text: String) {
    #expect(QRPayload.payload(for: text) == "メモ\n" + text)
    #expect(QRPayload.pack(text).payload == "メモ\n" + text)
}

@Test(arguments: [
    "https://example.com/a", "HTTP://example.com", "Meeting notes: next week", "メモ: 来週", "今日の議題: 印字", "plain text",
])
func otherTextIsLeftAsItIs(text: String) {
    #expect(QRPayload.payload(for: text) == text)
}
