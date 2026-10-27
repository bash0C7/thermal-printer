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

@Test(arguments: [[], [0], [255], [1, 2], [255, 255], [1, 2, 3], [0, 0, 0, 0]] as [[UInt8]])
func base45RoundTrips(bytes: [UInt8]) {
    #expect(Base45.decode(Base45.encode(Data(bytes))) == Data(bytes))
}

@Test func base45MatchesTheRFCExamples() {
    #expect(Base45.encode(Data("AB".utf8)) == "BB8")
    #expect(Base45.encode(Data("Hello!!".utf8)) == "%69 VD92EX0")
    #expect(Base45.encode(Data("ietf!".utf8)) == "QED8WEX0")
    #expect(Base45.decode("QED8WEX0") == Data("ietf!".utf8))
}

@Test func base45RejectsCharactersOutsideTheAlphabetAndOverflow() {
    #expect(Base45.decode("abc") == nil)
    #expect(Base45.decode("GGW") == nil)
    #expect(Base45.decode("A") == nil)
}

@Test func payloadRoundTripsThroughCompression() throws {
    let payload = try #require(QRPayload.encode(japanese))
    #expect(payload.hasPrefix("TP1:"))
    #expect(QRPayload.decode(payload) == japanese)
}

@Test func foreignPayloadsAreNotDecoded() {
    #expect(QRPayload.decode("https://example.com") == nil)
    #expect(QRPayload.decode("TP1:!!!") == nil)
}

@Test func payloadUsesOnlyTheAlphanumericQRAlphabet() throws {
    let payload = try #require(QRPayload.encode(japanese))
    #expect(payload.allSatisfy { "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ $%*+-./:".contains($0) })
}

@Test func shortTextIsPackedCompletely() {
    let packed = QRPayload.pack(japanese)
    #expect(packed.isComplete)
    #expect(packed.packedCharacters == japanese.count)
    #expect(QRCode.moduleCount(for: packed.payload).map { $0 <= QRPayload.maxCardModules } == true)
}

@Test func longTextIsCutToTheLargestPrefixThatFitsTheCard() throws {
    let text = varied(characters: 3000)
    let packed = QRPayload.pack(text)
    #expect(!packed.isComplete)
    #expect(packed.totalCharacters == 3000)
    #expect(packed.packedCharacters > 0)
    let modules = try #require(QRCode.moduleCount(for: packed.payload))
    #expect(modules <= QRPayload.maxCardModules)
    #expect(QRPayload.decode(packed.payload) == String(text.prefix(packed.packedCharacters)))
    let longer = try #require(QRPayload.encode(String(text.prefix(packed.packedCharacters + 20))))
    #expect((QRCode.moduleCount(for: longer) ?? .max) > QRPayload.maxCardModules)
}

@Test func packedPayloadFitsTheCardAndScansBackToTheOriginalText() throws {
    let text = varied(characters: 400)
    let packed = QRPayload.pack(text)
    let qr = try QRCode(packed.payload)
    #expect(qr.dotsPerModule >= 3)
    #expect(qr.sideDots <= Bitmap1.contentWidth - 16)
    #expect(QRPayload.decode(try QRDecoder.decode(qr.bitmap)) == String(text.prefix(packed.packedCharacters)))
}

@Test func englishFitsFarMoreCharactersThanJapanese() {
    let english = String(repeating: "The printer waits for the next card to arrive and then prints it. ", count: 60)
    let packedEnglish = QRPayload.pack(english)
    #expect(packedEnglish.isComplete)
    #expect(packedEnglish.totalCharacters > 3500)
}
