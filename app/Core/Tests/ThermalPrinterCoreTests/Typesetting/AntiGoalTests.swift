import Testing
@testable import ThermalPrinterCore

enum AntiGoal {
    static let longURL = "https://github.com/bash0C7/thermal-printer/issues/1?" + String(repeating: "q=abcdefghij&", count: 40)
    static let longWord = String(repeating: "Supercalifragilistic", count: 12)
    static let longDigits = String(repeating: "1234567890", count: 30)
    static let punctuatedJapanese = String(repeating: "「これは、テスト。」（括弧）ー長音！？『二重』…", count: 12)
    static let longCode = String(repeating: "    let veryLongIdentifierName = someFunction(argumentNumberOne, argumentNumberTwo, \"a string literal\")\n", count: 6)
    static let all: [(String, TextStyle)] = [
        (longURL, .body), (longWord, .body), (longDigits, .body), (punctuatedJapanese, .body),
        (punctuatedJapanese, .body.oblique), (longWord, .heading1), (longURL, .monospaced),
        (longCode, .monospaced), (longWord, .body.oblique), (longURL, .strong.oblique),
        (punctuatedJapanese, .heading1.oblique),
    ]
    static let indents = [0, 168, 240]
}

private func isolatedSinglePixelCount(_ bitmap: Bitmap1) -> Int {
    var count = 0
    for y in 0..<bitmap.height {
        for x in 0..<bitmap.width where bitmap[x: x, y: y] {
            var neighbours = 0
            for dy in -1...1 {
                for dx in -1...1 where dx != 0 || dy != 0 {
                    let nx = x + dx
                    let ny = y + dy
                    if nx >= 0, nx < bitmap.width, ny >= 0, ny < bitmap.height, bitmap[x: nx, y: ny] {
                        neighbours += 1
                    }
                }
            }
            if neighbours == 0 { count += 1 }
        }
    }
    return count
}

@Suite struct TypesettingAntiGoalTests {
    @Test(arguments: AntiGoal.all)
    func allInkStaysInsideThePrintableWidth(text: String, style: TextStyle) {
        let bmp = TextRenderer(margin: 8).render(text, style: style)
        #expect(bmp.blackPixels(inColumns: 0..<8).isEmpty)
        #expect(bmp.blackPixels(inColumns: 360..<384).isEmpty)
    }

    @Test(arguments: AntiGoal.all)
    func allInkStaysInsideTheNarrowedWidthToo(text: String, style: TextStyle) {
        for indent in AntiGoal.indents {
            let bmp = TextRenderer(margin: 8).render(text, style: style, indent: indent)
            #expect(bmp.blackPixels(inColumns: 0..<(8 + indent)).isEmpty)
            #expect(bmp.blackPixels(inColumns: 360..<384).isEmpty)
            #expect(bmp.blackPixels(inColumns: 0..<384).isEmpty == false)
        }
    }

    @Test(arguments: AntiGoal.all)
    func longTokensAreWrappedNotTruncated(text: String, style: TextStyle) {
        let lines = LineBreaker(width: 368).lines(text, style: style)
        #expect(lines.joined() == text.replacingOccurrences(of: "\n", with: ""))
        #expect(lines.count > 1)
    }

    @Test func noLineStartsWithALineStartForbiddenCharacter() {
        for width in [200, 368] {
            let lines = LineBreaker(width: width).lines(AntiGoal.punctuatedJapanese, style: .body)
            for line in lines.dropFirst() {
                #expect(!Kinsoku.lineStartForbidden.contains(line.first!))
            }
        }
    }

    @Test func noLineStartsWithALineStartForbiddenCharacterWhenSlanted() {
        for width in [200, 368] {
            let lines = LineBreaker(width: width).lines(AntiGoal.punctuatedJapanese, style: .body.oblique)
            for line in lines.dropFirst() {
                #expect(!Kinsoku.lineStartForbidden.contains(line.first!))
            }
        }
    }

    @Test func noLineEndsWithALineEndForbiddenCharacter() {
        for width in [200, 368] {
            let lines = LineBreaker(width: width).lines(AntiGoal.punctuatedJapanese, style: .body)
            for line in lines.dropLast() {
                #expect(!Kinsoku.lineEndForbidden.contains(line.last!))
            }
        }
    }

    @Test func noLineStartsWithAForbiddenCharacterAcrossManyWidths() {
        for width in stride(from: 120, through: 368, by: 8) {
            for style in [TextStyle.body, .body.oblique, .heading1, .small] {
                let lines = LineBreaker(width: width).lines(AntiGoal.punctuatedJapanese, style: style)
                for line in lines.dropFirst() {
                    #expect(!Kinsoku.lineStartForbidden.contains(line.first!))
                }
            }
        }
    }

    @Test(arguments: [AntiGoal.longURL, AntiGoal.punctuatedJapanese])
    func inkStaysInsideAcrossManyNarrowedWidths(text: String) {
        for indent in stride(from: 0, through: 300, by: 20) {
            for style in [TextStyle.body, .body.oblique, .heading2.oblique, .monospaced] {
                let bmp = TextRenderer(margin: 8).render(text, style: style, indent: indent)
                #expect(bmp.blackPixels(inColumns: 0..<(8 + indent)).isEmpty)
                #expect(bmp.blackPixels(inColumns: 360..<384).isEmpty)
            }
        }
    }

    @Test func renderedHeightGrowsWithTheNumberOfLines() {
        let one = TextRenderer(margin: 8).render("あ", style: .body)
        let many = TextRenderer(margin: 8).render(AntiGoal.longWord, style: .body)
        #expect(one.height > 0)
        #expect(many.height > one.height)
    }

    @Test func renderingNothingStillProducesOneBlankLine() {
        let bmp = TextRenderer(margin: 8).render("", style: .body)
        #expect(bmp.height > 0)
        #expect(bmp.blackPixels(inColumns: 0..<384).isEmpty)
    }

    @Test func textIsThresholdedNotDithered() {
        let bmp = TextRenderer(margin: 8).render("あ", style: .body)
        #expect(isolatedSinglePixelCount(bmp) < 4)
    }

    @Test func obliqueRendersDifferentInkFromUpright() {
        let upright = TextRenderer(margin: 8).render("lllll", style: .body)
        let slanted = TextRenderer(margin: 8).render("lllll", style: .body.oblique)
        #expect(upright != slanted)
    }
}
