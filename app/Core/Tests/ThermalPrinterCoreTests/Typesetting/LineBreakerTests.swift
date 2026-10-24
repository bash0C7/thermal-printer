import Testing
@testable import ThermalPrinterCore

@Suite struct TypesettingLineBreakerTests {

    @Test func shortTextStaysOnOneLine() {
        #expect(LineBreaker(width: 368).lines("こんにちは", style: .body) == ["こんにちは"])
    }

    @Test func newlinesSeparateParagraphsAndEmptyParagraphsKeepOneBlankLine() {
        #expect(LineBreaker(width: 368).lines("あ\n\nい", style: .body) == ["あ", "", "い"])
    }

    @Test func emptyTextIsOneBlankLine() {
        #expect(LineBreaker(width: 368).lines("", style: .body) == [""])
    }

    @Test(arguments: AntiGoal.all)
    func wrappingNeverLosesACharacter(text: String, style: TextStyle) {
        for width in [200, 368] {
            #expect(LineBreaker(width: width).lines(text, style: style).joined() == text.replacingOccurrences(of: "\n", with: ""))
        }
    }

    @Test func prolongedSoundMarkNeverStartsALine() {
        let text = String(repeating: "あ", count: 22) + "ー" + String(repeating: "い", count: 40)
        for width in stride(from: 200, through: 368, by: 4) {
            for line in LineBreaker(width: width).lines(text, style: .body).dropFirst() {
                #expect(line.first != "ー")
            }
        }
    }

    @Test(arguments: ["っ", "ゃ", "ょ", "ッ", "ァ", "、", "。", "」", "）"])
    func everyLineStartForbiddenCharacterIsKeptOffTheLineStart(forbidden: String) {
        let text = String(repeating: "あ", count: 17) + forbidden + String(repeating: "い", count: 30)
        for width in stride(from: 120, through: 368, by: 2) {
            for line in LineBreaker(width: width).lines(text, style: .body).dropFirst() {
                #expect(line.first.map { !Kinsoku.lineStartForbidden.contains($0) } ?? true)
            }
        }
    }

    @Test(arguments: ["「", "『", "（", "【"])
    func everyLineEndForbiddenCharacterIsKeptOffTheLineEnd(forbidden: String) {
        let text = String(repeating: "あ", count: 17) + forbidden + String(repeating: "い", count: 30)
        for width in stride(from: 120, through: 368, by: 2) {
            for line in LineBreaker(width: width).lines(text, style: .body).dropLast() {
                #expect(line.last.map { !Kinsoku.lineEndForbidden.contains($0) } ?? true)
            }
        }
    }

    @Test func punctuationAfterAForcedWrapOfALongTokenDoesNotStartALine() {
        let token = String(repeating: "ABCDEFGHIJKLMNOPQRSTUVWXYZ", count: 3)
        let text = token + "。次の文です。" + token + "、続き"
        for width in stride(from: 150, through: 368, by: 3) {
            for line in LineBreaker(width: width).lines(text, style: .body).dropFirst() {
                #expect(line.first.map { !Kinsoku.lineStartForbidden.contains($0) } ?? true)
            }
        }
    }

    @Test func aRunOfForbiddenCharactersLongerThanALineStillTerminatesWithoutLosingText() {
        let text = "あ" + String(repeating: "。", count: 60) + "い"
        let lines = LineBreaker(width: 100).lines(text, style: .body)
        #expect(lines.joined() == text)
        #expect(lines.count > 1)
    }

    @Test func aWidthSmallerThanOneGlyphPutsOneCharacterOnEachLine() {
        let lines = LineBreaker(width: 10).lines("あいう", style: .body)
        #expect(lines == ["あ", "い", "う"])
    }

    @Test func spacesAreWrappedAtWordBoundaries() {
        let text = String(repeating: "word ", count: 30)
        let lines = LineBreaker(width: 368).lines(text, style: .body)
        #expect(lines.joined() == text)
        for line in lines.dropLast() {
            #expect(line.hasSuffix(" "))
        }
    }

    @Test func obliqueNeverFitsMoreThanUpright() {
        let text = String(repeating: "あ", count: 80)
        let upright = LineBreaker(width: 368).lines(text, style: .body)
        let slanted = LineBreaker(width: 368).lines(text, style: .body.oblique)
        #expect(slanted.count >= upright.count)
    }

    @Test func everyStylePostScriptNameResolvesToItsRealFont() {
        for style in [TextStyle.small, .body, .large, .strong, .heading1, .heading2, .heading3, .monospaced] {
            #expect(style.resolvedPostScriptName == style.fontName)
        }
    }
}
