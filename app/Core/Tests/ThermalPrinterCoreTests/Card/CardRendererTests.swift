import Foundation
import Testing
@testable import ThermalPrinterCore

enum CardAntiGoal {
    static let longURL = "https://example.com/" + String(repeating: "path/segment?q=abcdefghij&", count: 8)
    static let narrowColumnURL = "https://example.com/" + String(repeating: "a", count: 400)
    static let stackedURL = "https://example.com/" + String(repeating: "a", count: 600)
    static let longRepo = "bash0C7/" + String(repeating: "thermal-printer-", count: 8)
    static let longTitle = String(repeating: "「これは、長い題名。」（括弧）ー長音！？", count: 6)
    static let longChannel = "#" + String(repeating: "dev-printer-", count: 10)
    static let punctuated = String(repeating: "「これは、テスト。」（括弧）ー長音！？『二重』…", count: 6)

    static func github(
        url: String? = "https://github.com/bash0C7/thermal-printer/issues/12",
        lines: [String] = ["bash0C7/thermal-printer"],
        emphasis: String? = "#12",
        sublines: [String] = ["open ・ 更新 2日前"],
        title: String = "長い出力のときに GUI で警告を出す",
        sections: [Card.Section] = [Card.Section(label: nil, text: "概要"), Card.Section(label: "最新コメント", text: "コメント")],
        note: String? = nil
    ) -> Card {
        Card(
            kind: .github, url: url,
            header: Card.Header(lines: lines, emphasis: emphasis, sublines: sublines),
            title: title, sections: sections, note: note
        )
    }

    static let all: [Card] = [
        github(url: longURL, title: longURL, sections: [Card.Section(label: longURL, text: longURL)]),
        github(url: narrowColumnURL, lines: [longRepo], emphasis: longChannel, sublines: [longURL, longURL]),
        github(url: stackedURL, lines: [longRepo], emphasis: longChannel, sublines: [longURL, longURL]),
        github(lines: [longRepo]),
        github(title: longTitle),
        github(emphasis: longChannel),
        github(emphasis: String(repeating: "9", count: 80)),
        github(sublines: [longURL, punctuated]),
        github(sections: [Card.Section(label: punctuated, text: punctuated), Card.Section(label: nil, text: longURL)]),
        github(note: longURL),
        github(lines: [longRepo], emphasis: longChannel, sublines: [longURL], title: longTitle,
               sections: [Card.Section(label: longRepo, text: longURL)], note: punctuated),
        github(url: nil, lines: [longRepo], emphasis: longChannel, title: longURL),
        github(url: nil, title: punctuated, sections: [Card.Section(label: nil, text: punctuated)]),
    ]
}

@Suite struct CardRendererTests {
    private let renderer = CardRenderer(margin: 8)

    @Test func qrSitsInTheTopRightCorner() throws {
        let r = try renderer.render(CardFixture.card("github"))
        let qr = try #require(r.qrFrame)
        #expect(qr.maxX <= 360)
        #expect(qr.minY == r.topPadding)
        #expect(r.headerTextFrame.maxX <= qr.minX - 8)
    }

    @Test func qrRightEdgeIsTheContentWidthMinusTheMarginAndItsInkIsInsideTheContentWidth() throws {
        let r = try renderer.render(CardFixture.card("github"))
        let qr = try #require(r.qrFrame)
        #expect(qr.maxX == Bitmap1.contentWidth - 8)
        #expect(r.bitmap.blackPixels(inColumns: Bitmap1.contentWidth..<Bitmap1.width).isEmpty)
        #expect(!r.bitmap.blackPixels(in: qr).isEmpty)
    }

    @Test func reminderCardHasNoQR() throws {
        #expect(try renderer.render(CardFixture.card("reminder")).qrFrame == nil)
    }

    @Test(arguments: CardAntiGoal.all)
    func cardInkStaysInsideThePrintableWidth(card: Card) throws {
        let bmp = try renderer.render(card).bitmap
        #expect(bmp.blackPixels(inColumns: 0..<8).isEmpty)
        #expect(bmp.blackPixels(inColumns: 360..<384).isEmpty)
    }

    @Test(arguments: CardAntiGoal.all)
    func headerTextNeverEntersTheQRColumnOrItsGap(card: Card) throws {
        let r = try renderer.render(card)
        guard let qr = r.qrFrame, r.headerTextFrame.minY < qr.maxY else { return }
        let gap = PixelRect(x: r.headerTextFrame.maxX, y: qr.minY, width: qr.minX - r.headerTextFrame.maxX, height: qr.height)
        #expect(gap.width >= 8)
        #expect(r.bitmap.blackPixels(in: gap).isEmpty)
    }

    @Test(arguments: ["github", "slack", "url"])
    func printedQRStillDecodes(name: String) throws {
        let card = try CardFixture.card(name)
        let r = try renderer.render(card)
        let qr = try #require(r.qrFrame)
        #expect(try QRDecoder.decode(r.bitmap.crop(qr)) == card.url)
    }

    @Test(arguments: ["github", "slack", "url"])
    func wholeCardStillDecodesTheQR(name: String) throws {
        let card = try CardFixture.card(name)
        let r = try renderer.render(card)
        #expect(try QRDecoder.decode(r.bitmap) == card.url)
    }

    @Test(arguments: ["github", "slack", "url"])
    func qrKeepsItsFullSizeWithAtLeastThreeDotsPerModule(name: String) throws {
        let card = try CardFixture.card(name)
        let r = try renderer.render(card)
        let qr = try QRCode(try #require(card.url))
        let frame = try #require(r.qrFrame)
        #expect(frame.width == qr.sideDots)
        #expect(frame.height == qr.sideDots)
        #expect(qr.dotsPerModule >= 3)
    }

    @Test(arguments: ["slack", "url"])
    func headerBandGrowsToTheQRSide(name: String) throws {
        let r = try renderer.render(CardFixture.card(name))
        let qr = try #require(r.qrFrame)
        #expect(qr.height > 128)
        let stacked = r.headerTextFrame.minY >= qr.maxY
        let expected = stacked ? r.headerTextFrame.maxY - qr.minY : max(qr.height, r.headerTextFrame.height)
        #expect(r.headerFrame.height == expected)
        #expect(r.headerFrame.height >= qr.height)
        #expect(r.titleFrame.minY >= qr.maxY)
        #expect(r.titleFrame.minY >= r.headerTextFrame.maxY)
    }

    @Test func titleStartsBelowTheHeaderAndSectionsBelowTheTitle() throws {
        let r = try renderer.render(CardFixture.card("github"))
        #expect(r.titleFrame.minY >= r.headerFrame.maxY)
        #expect(r.bitmap.height > r.titleFrame.maxY)
        #expect(!r.bitmap.blackPixels(in: r.titleFrame).isEmpty)
    }

    @Test func headerBandIsAtLeastAsTallAsEitherSide() throws {
        let r = try renderer.render(CardFixture.card("github"))
        let qr = try #require(r.qrFrame)
        #expect(r.headerFrame.height == max(qr.height, r.headerTextFrame.height))
    }

    @Test func titleIsSetInTheLargestHeavyStyle() throws {
        let r = try renderer.render(CardFixture.card("github"))
        let title = r.bitmap.crop(r.titleFrame)
        let ink = title.blackPixels(inColumns: 0..<384)
        let top = ink.map(\.y).min() ?? 0
        let bottom = ink.map(\.y).max() ?? 0
        #expect(bottom - top >= 24)
    }

    @Test func tallQRMovesTheHeaderTextBelowItAndKeepsTheQRTopRight() throws {
        let card = CardAntiGoal.github(url: CardAntiGoal.stackedURL)
        let qr = try QRCode(CardAntiGoal.stackedURL)
        #expect(qr.sideDots > 264)
        let r = try renderer.render(card)
        let frame = try #require(r.qrFrame)
        #expect(frame.maxX <= 360)
        #expect(frame.minY == r.topPadding)
        #expect(r.headerTextFrame.minY >= frame.maxY)
        #expect(r.headerTextFrame.width == 352)
        #expect(try QRDecoder.decode(r.bitmap.crop(frame)) == CardAntiGoal.stackedURL)
    }

    @Test func unreadablyWidePayloadFailsLoudlyInsteadOfShrinking() {
        let card = CardAntiGoal.github(url: "https://example.com/" + String(repeating: "a", count: 2000))
        #expect(throws: QRCode.Failure.self) {
            try renderer.render(card)
        }
    }

    @Test func labelledSectionIsTallerThanTheSameSectionWithoutALabel() throws {
        let plain = try renderer.render(CardAntiGoal.github(sections: [Card.Section(label: nil, text: "本文")]))
        let labelled = try renderer.render(CardAntiGoal.github(sections: [Card.Section(label: "最新コメント", text: "本文")]))
        #expect(labelled.bitmap.height > plain.bitmap.height + 16)
    }

    @Test func labelIsUnderlinedWithAThickRule() throws {
        let r = try renderer.render(CardAntiGoal.github(sections: [Card.Section(label: "最新コメント", text: "本文")]))
        var longestRun = 0
        for y in r.titleFrame.maxY..<r.bitmap.height {
            var run = 0
            for x in 0..<384 {
                run = r.bitmap[x: x, y: y] ? run + 1 : 0
                longestRun = max(longestRun, run)
            }
        }
        #expect(longestRun >= 60)
    }

    @Test func noteAddsASmallLineAtTheBottom() throws {
        let without = try renderer.render(CardAntiGoal.github())
        let withNote = try renderer.render(CardAntiGoal.github(note: "取得できません"))
        #expect(withNote.bitmap.height > without.bitmap.height)
        #expect(withNote.noteFrame != nil)
        #expect(without.noteFrame == nil)
    }

    @Test func absentEmphasisAndEmptySectionsStillRender() throws {
        let r = try renderer.render(CardAntiGoal.github(emphasis: nil, sublines: [], sections: []))
        #expect(r.bitmap.height > r.titleFrame.maxY)
    }

    @Test func longerTitlesMakeTallerCards() throws {
        let short = try renderer.render(CardAntiGoal.github(title: "短い"))
        let long = try renderer.render(CardAntiGoal.github(title: CardAntiGoal.longTitle))
        #expect(long.bitmap.height > short.bitmap.height)
    }

    @Test func rendersAreDeterministic() throws {
        let card = try CardFixture.card("slack")
        #expect(try renderer.render(card).bitmap == renderer.render(card).bitmap)
    }
}
