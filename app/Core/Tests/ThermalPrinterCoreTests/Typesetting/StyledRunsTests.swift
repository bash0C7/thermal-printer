import Testing
@testable import ThermalPrinterCore

enum MixedRuns {
    static let urlInBold: [StyledRun] = [
        StyledRun("参照: ", style: .body),
        StyledRun(AntiGoal.longURL, style: .strong),
        StyledRun(" を見る。", style: .body),
    ]
    static let punctuatedMix: [StyledRun] = (0..<12).flatMap { _ in
        [
            StyledRun("「これは、", style: .body),
            StyledRun("テスト。」（括弧）", style: .strong.oblique),
            StyledRun("ー長音！？", style: .monospaced),
            StyledRun("『二重』…", style: .body.oblique),
        ]
    }
    static let slantedEdge: [StyledRun] = [
        StyledRun(String(repeating: "lllll", count: 30), style: .body.oblique),
        StyledRun(String(repeating: "WWWW", count: 30), style: .strong.oblique),
    ]
    static let heading: [StyledRun] = [
        StyledRun("Supercalifragilistic", style: .heading1),
        StyledRun(String(repeating: "コード", count: 10), style: .monospaced),
        StyledRun(String(repeating: "Supercalifragilistic", count: 4), style: .heading1.oblique),
    ]
    static let all: [[StyledRun]] = [urlInBold, punctuatedMix, slantedEdge, heading]
    static let widths = [120, 200, 368]
}

private func joined(_ runs: [StyledRun]) -> String {
    runs.map(\.text).joined()
}

@Suite struct StyledRunsTests {
    @Test(arguments: MixedRuns.all)
    func mixedRunsKeepEveryCharacterInOrder(runs: [StyledRun]) {
        let lines = LineBreaker(width: 368).lines(runs: runs)
        #expect(lines.map(joined).joined() == joined(runs))
        #expect(lines.count > 1)
    }

    @Test(arguments: MixedRuns.all)
    func mixedRunsInkStaysInsideThePrintableWidth(runs: [StyledRun]) {
        for indent in [0, 100, 184] {
            let bmp = TextRenderer(margin: 8).render(runs: runs, indent: indent)
            #expect(bmp.blackPixels(inColumns: 0..<(8 + indent)).isEmpty)
            #expect(bmp.blackPixels(inColumns: 360..<384).isEmpty)
            #expect(bmp.blackPixels(inColumns: 0..<384).isEmpty == false)
        }
    }

    @Test(arguments: MixedRuns.all)
    func noMixedLineStartsWithALineStartForbiddenCharacter(runs: [StyledRun]) {
        for width in MixedRuns.widths {
            for line in LineBreaker(width: width).lines(runs: runs).dropFirst() {
                #expect(!Kinsoku.lineStartForbidden.contains(joined(line).first!))
            }
        }
    }

    @Test(arguments: MixedRuns.all)
    func noMixedLineEndsWithALineEndForbiddenCharacter(runs: [StyledRun]) {
        for width in MixedRuns.widths {
            for line in LineBreaker(width: width).lines(runs: runs).dropLast() {
                #expect(!Kinsoku.lineEndForbidden.contains(joined(line).last!))
            }
        }
    }

    @Test func eachCharacterKeepsTheStyleOfItsRun() {
        let runs = [
            StyledRun(String(repeating: "A", count: 60), style: .body),
            StyledRun(String(repeating: "B", count: 60), style: .strong),
        ]
        let lines = LineBreaker(width: 200).lines(runs: runs)
        for run in lines.flatMap({ $0 }) {
            let expected: TextStyle = run.text.hasPrefix("A") ? .body : .strong
            #expect(run.style == expected)
            #expect(Set(run.text).count == 1)
        }
    }

    @Test func aSingleRunBreaksLikeThePlainBreaker() {
        let text = AntiGoal.punctuatedJapanese
        for width in [200, 368] {
            let plain = LineBreaker(width: width).lines(text, style: .body)
            let styled = LineBreaker(width: width).lines(runs: [StyledRun(text, style: .body)]).map(joined)
            #expect(styled == plain)
        }
    }

    @Test func hardNewlineStartsANewLine() {
        let runs = [StyledRun("一行目\n二行目", style: .body)]
        let lines = LineBreaker(width: 368).lines(runs: runs).map(joined)
        #expect(lines == ["一行目", "二行目"])
    }

    @Test func aBlankRunStillMakesOneLineOfItsHeight() {
        let bmp = TextRenderer(margin: 8).render(runs: [StyledRun("", style: .large)])
        #expect(bmp.height == TextStyle.large.lineHeight)
        #expect(bmp.blackPixels(inColumns: 0..<384).isEmpty)
    }

    @Test func aLineIsAsTallAsItsTallestRun() {
        let runs = [StyledRun("小", style: .small), StyledRun("大", style: .heading1)]
        let bmp = TextRenderer(margin: 8).render(runs: runs)
        #expect(bmp.height == TextStyle.heading1.lineHeight)
    }

    @Test func aSingleRunRendersLikeThePlainRenderer() {
        let text = "こんにちは、世界。Hello"
        let plain = TextRenderer(margin: 8).render(text, style: .body)
        let styled = TextRenderer(margin: 8).render(runs: [StyledRun(text, style: .body)])
        #expect(styled == plain)
    }

    @Test func boldAndPlainRunsInOneLineDrawDifferentInkFromAllPlain() {
        let plain = TextRenderer(margin: 8).render(runs: [StyledRun("abcdef", style: .body)])
        let mixed = TextRenderer(margin: 8).render(runs: [
            StyledRun("abc", style: .body), StyledRun("def", style: .strong.oblique),
        ])
        #expect(plain != mixed)
    }
}
