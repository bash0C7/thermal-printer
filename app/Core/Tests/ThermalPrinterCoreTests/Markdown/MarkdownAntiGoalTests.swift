import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import ThermalPrinterCore

enum MarkdownAntiGoal {
    static let japanese = "「これは、テスト。」（括弧）ー長音！？『二重』…"
    static let longURL = "https://example.com/very/long/path/" + String(repeating: "segment/", count: 12)

    static let all: [String] = [
        (0..<20).map { String(repeating: "  ", count: $0) + "- 入れ子の深いリスト\($0)、とても長い項目の本文が続く" }.joined(separator: "\n"),
        "```\n" + String(repeating: "let x = veryLongIdentifierWithoutSpaces", count: 8) + "\n```",
        "| 列A | 列B |\n|---|---|\n| " + String(repeating: "長いセル", count: 30) + " | b |",
        "# " + String(repeating: "Supercalifragilistic", count: 6),
        "> " + String(repeating: "引用の中の、長い文。", count: 20),
        "- [ ] " + String(repeating: "https://example.com/very/long/path/", count: 6),
        "***" + String(repeating: "太字斜体", count: 40) + "***",
        "## " + String(repeating: japanese, count: 6),
        "### " + longURL,
        "#### " + String(repeating: "Supercalifragilistic", count: 6),
        (0..<8).map { String(repeating: "> ", count: $0 + 1) + "入れ子の引用\($0)、" + japanese + longURL }.joined(separator: "\n>\n"),
        String(repeating: japanese, count: 12),
        "**" + String(repeating: japanese, count: 6) + "** と *" + longURL + "* と `" + longURL + "` の混在",
        "太字 **" + longURL + "** 斜体 *" + String(repeating: "Supercalifragilistic", count: 6) + "* コード `" + String(repeating: "x", count: 200) + "`",
        (1...12).map { "\($0 * 100000). 番号付きの項目、" + japanese + longURL }.joined(separator: "\n"),
        "- 外\n  > 引用\n  > - 引用の中のリスト、" + japanese + longURL + "\n    - [x] さらに入れ子、" + longURL,
        "1. 一\n   1. 二\n      1. 三\n         1. 四\n            1. 五\n               1. 六\n                  1. 七、" + japanese + longURL,
        "[" + longURL + "](" + longURL + ")",
        "![" + longURL + "](" + longURL + ")",
        "前の行、\n次の行" + longURL + "\\\nバックスラッシュで改行" + String(repeating: "あ", count: 80),
        "---\n" + longURL + "\n***",
        "```\n" + (0..<10).map { "    " + String(repeating: "indent", count: $0 + 1) }.joined(separator: "\n") + "\n```",
        "| a | b | c | d |\n|---|---|---|---|\n| " + String(repeating: "x", count: 100) + " | " + longURL + " | `code` | **b** |",
        "<div>" + longURL + "</div>",
    ]
}

private func writePNG(_ image: CGImage, to url: URL) throws {
    let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil))
    CGImageDestinationAddImage(destination, image, nil)
    #expect(CGImageDestinationFinalize(destination))
}

@Suite struct MarkdownAntiGoalTests {
    @Test(arguments: MarkdownAntiGoal.all)
    func markdownInkStaysInsideThePrintableWidth(md: String) {
        let bmp = MarkdownRenderer(margin: 8).render(md)
        #expect(bmp.height > 0)
        #expect(bmp.blackPixels(inColumns: 0..<8).isEmpty)
        #expect(bmp.blackPixels(inColumns: 360..<384).isEmpty)
        #expect(bmp.blackPixels(inColumns: 0..<384).isEmpty == false)
    }

    @Test(arguments: MarkdownAntiGoal.all)
    func noWrappedMarkdownLineStartsWithALineStartForbiddenCharacter(md: String) {
        for block in MarkdownRenderer(margin: 8).wrappedLines(md) {
            for line in block.dropFirst() {
                #expect(!Kinsoku.lineStartForbidden.contains(line.first!))
            }
        }
    }

    @Test(arguments: MarkdownAntiGoal.all)
    func noWrappedMarkdownLineEndsWithALineEndForbiddenCharacter(md: String) {
        for block in MarkdownRenderer(margin: 8).wrappedLines(md) {
            for line in block.dropLast() {
                #expect(!Kinsoku.lineEndForbidden.contains(line.last!))
            }
        }
    }

    @Test func prolongedSoundMarkNeverStartsALineInAList() {
        for count in 6...16 {
            let text = String(repeating: "あ", count: count) + "ー" + String(repeating: "い", count: 30)
            for md in ["- " + text, "> " + text, "1. " + text, "**" + text + "**"] {
                let blocks = MarkdownRenderer(margin: 8).wrappedLines(md)
                #expect(blocks.isEmpty == false)
                for line in blocks.flatMap({ $0 }).dropFirst() {
                    #expect(line.first != "ー")
                }
            }
        }
    }

    @Test func wrappedLinesLoseNoCharacterOfLongTokensInsideInlineMarkup() {
        let md = "**" + MarkdownAntiGoal.longURL + "** *" + MarkdownAntiGoal.japanese + "* `" + String(repeating: "x", count: 100) + "`"
        let expected = MarkdownAntiGoal.longURL + " " + MarkdownAntiGoal.japanese + " " + String(repeating: "x", count: 100)
        let blocks = MarkdownRenderer(margin: 8).wrappedLines(md)
        #expect(blocks.count == 1)
        #expect(blocks[0].joined().replacingOccurrences(of: " ", with: "") == expected.replacingOccurrences(of: " ", with: ""))
        #expect(blocks[0].count > 1)
    }

    @Test func nestedIndentStopsAtHalfOfThePrintableWidth() {
        let md = (0..<20).map { String(repeating: "  ", count: $0) + "- 項目\($0)" }.joined(separator: "\n")
        let insets = MarkdownRenderer(margin: 8).layout(md).map(\.textInset)
        #expect(insets.max()! <= 184 + 40)
        #expect(insets.max()! >= 184)
        #expect(insets == insets.sorted())
    }

    @Test func nestedQuotesAndListsTogetherStillLeaveRoomForText() {
        let md = (0..<10).map { String(repeating: "> ", count: $0 + 1) + "- 項目" }.joined(separator: "\n")
        let insets = MarkdownRenderer(margin: 8).layout(md).map(\.textInset)
        #expect(insets.max()! <= 184 + 40)
    }

    @Test func aLocalImageIsEmbeddedInsideThePrintableWidth() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "markdown-image-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try writePNG(ImageLoader.sampleImage(), to: directory.appending(path: "sample.png"))

        let withImage = MarkdownRenderer(margin: 8, baseURL: directory).render("![写真](sample.png)")
        let absolute = MarkdownRenderer(margin: 8).render("![写真](\(directory.appending(path: "sample.png").path))")
        for bmp in [withImage, absolute] {
            #expect(bmp.height > 200)
            #expect(bmp.blackPixels(inColumns: 0..<8).isEmpty)
            #expect(bmp.blackPixels(inColumns: 360..<384).isEmpty)
            #expect(bmp.blackPixels(inColumns: 8..<360).isEmpty == false)
        }
    }

    @Test func anImageThatCannotBeLoadedFallsBackToItsAltText() {
        let md = "![代替テキスト](missing/not-here.png)"
        #expect(MarkdownRenderer.plainText(md) == "代替テキスト")
        let bmp = MarkdownRenderer(margin: 8, baseURL: FileManager.default.temporaryDirectory).render(md)
        #expect(bmp.height < 100)
        #expect(bmp.blackPixels(inColumns: 0..<8).isEmpty)
        #expect(bmp.blackPixels(inColumns: 360..<384).isEmpty)
    }

    @Test func aRemoteImageIsNeverFetched() {
        let md = "![遠隔](https://example.com/a.png)"
        #expect(MarkdownRenderer.plainText(md) == "遠隔")
    }
}
