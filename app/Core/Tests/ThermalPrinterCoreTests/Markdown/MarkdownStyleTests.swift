import Testing
@testable import ThermalPrinterCore

private func rowBlackCount(_ bitmap: Bitmap1, row y: Int, columns: Range<Int>) -> Int {
    columns.reduce(0) { $0 + (bitmap[x: $1, y: y] ? 1 : 0) }
}

private func ruleRows(_ bitmap: Bitmap1) -> [Int] {
    (0..<bitmap.height).filter { rowBlackCount(bitmap, row: $0, columns: 8..<360) >= 344 }
}

private func totalBlack(_ bitmap: Bitmap1) -> Int {
    bitmap.bytes.reduce(0) { $0 + $1.nonzeroBitCount }
}

private func leftmostInk(_ bitmap: Bitmap1) -> Int? {
    for x in 0..<Bitmap1.width {
        for y in 0..<bitmap.height where bitmap[x: x, y: y] { return x }
    }
    return nil
}

private func hasSolidSquare(_ bitmap: Bitmap1, size: Int, columns: Range<Int>) -> Bool {
    guard bitmap.height >= size else { return false }
    for top in 0...(bitmap.height - size) {
        for left in columns.lowerBound...(columns.upperBound - size) {
            var solid = true
            for dy in 0..<size where solid {
                for dx in 0..<size where !bitmap[x: left + dx, y: top + dy] {
                    solid = false
                    break
                }
            }
            if solid { return true }
        }
    }
    return false
}

private func fullyBlackColumns(_ bitmap: Bitmap1, in columns: Range<Int>) -> [Int] {
    columns.filter { x in (0..<bitmap.height).allSatisfy { bitmap[x: x, y: $0] } }
}

@Suite struct MarkdownStyleTests {
    @Test func h2HasAThickRuleUnderIt() {
        let bmp = MarkdownRenderer(margin: 8).render("## 見出し")
        let rows = ruleRows(bmp)
        #expect(rows.count >= 3)
        #expect(rows.last == bmp.height - 1)
        #expect(rows == Array(rows.first!...rows.last!))
    }

    @Test func h3HasNoRule() {
        let bmp = MarkdownRenderer(margin: 8).render("### 見出し")
        #expect(ruleRows(bmp).isEmpty)
    }

    @Test func h1AndH4ToH6HaveNoRule() {
        for md in ["# 見出し", "#### 見出し", "##### 見出し", "###### 見出し"] {
            #expect(ruleRows(MarkdownRenderer(margin: 8).render(md)).isEmpty)
        }
    }

    @Test func headingsShrinkFromH1ToH3AndStayTheSameFromH3ToH6() {
        let height = { (md: String) in MarkdownRenderer(margin: 8).render(md).height }
        let h1 = height("# あ")
        let h2 = height("## あ")
        let h3 = height("### あ")
        let body = height("あ")
        #expect(h1 > h2 - 6)
        #expect(h2 - 6 > h3)
        #expect(h3 > body)
        #expect(height("#### あ") == h3)
        #expect(height("##### あ") == h3)
        #expect(height("###### あ") == h3)
    }

    @Test func strongInkIsHeavierThanPlainInk() {
        let plain = totalBlack(MarkdownRenderer(margin: 8).render("あいうえお"))
        let strong = totalBlack(MarkdownRenderer(margin: 8).render("**あいうえお**"))
        #expect(strong > plain)
    }

    @Test func emphasisIsSlantedAndBoldItalicDiffersFromBoth() {
        let plain = MarkdownRenderer(margin: 8).render("lllll")
        let italic = MarkdownRenderer(margin: 8).render("*lllll*")
        let bold = MarkdownRenderer(margin: 8).render("**lllll**")
        let both = MarkdownRenderer(margin: 8).render("***lllll***")
        #expect(italic != plain)
        #expect(both != italic)
        #expect(both != bold)
    }

    @Test func inlineMarkupMakesRunsOfTheMatchingStyles() {
        let blocks = MarkdownRenderer(margin: 8).layout("通常 **太字** *斜体* `code` ***両方***")
        guard case .text(let runs) = blocks[0].content else {
            Issue.record("expected a text block")
            return
        }
        let styleOf = { (text: String) in runs.first { $0.text.contains(text) }?.style }
        #expect(styleOf("通常") == .body)
        #expect(styleOf("太字") == .strong)
        #expect(styleOf("斜体") == .body.oblique)
        #expect(styleOf("code")?.fontName == TextStyle.monospaced.fontName)
        #expect(styleOf("両方") == .strong.oblique)
    }

    @Test func bulletsAreSolidDiscsLeftOfTheText() {
        let list = MarkdownRenderer(margin: 8).render("- あ")
        let paragraph = MarkdownRenderer(margin: 8).render("あ")
        #expect(hasSolidSquare(list, size: 6, columns: 8..<24))
        #expect(!hasSolidSquare(paragraph, size: 6, columns: 8..<24))
    }

    @Test func nestedListsIndentSixteenDotsPerLevel() {
        let insets = MarkdownRenderer(margin: 8).layout("- a\n  - b\n    - c").map(\.textInset)
        #expect(insets == [16, 32, 48])
    }

    @Test func orderedListsShowTheirNumbers() {
        #expect(MarkdownRenderer.plainText("1. a\n2. b") == "1. a\n2. b")
        #expect(MarkdownRenderer.plainText("3) a\n4) b") == "3. a\n4. b")
    }

    @Test func checkboxesUseBallotBoxGlyphs() {
        #expect(MarkdownRenderer.plainText("- [ ] a\n- [x] b") == "☐ a\n☑ b")
    }

    @Test func checkboxesGetNoBullet() {
        let bmp = MarkdownRenderer(margin: 8).render("- [ ] a")
        #expect(!hasSolidSquare(bmp, size: 6, columns: 8..<24))
    }

    @Test func linksShowOnlyTheirText() {
        #expect(MarkdownRenderer.plainText("[設計書](https://example.com)") == "設計書")
        #expect(MarkdownRenderer.plainText("[**太い** 設計書](https://example.com/a)") == "太い 設計書")
    }

    @Test func quotesHaveAThickBarOnTheLeft() {
        let bmp = MarkdownRenderer(margin: 8).render("> 引用")
        let columns = fullyBlackColumns(bmp, in: 0..<40)
        #expect(columns.count >= 4)
        #expect(columns.first == 8)
        #expect(MarkdownRenderer(margin: 8).layout("> 引用")[0].textInset == 15)
    }

    @Test func aBarRunsUnbrokenThroughTheGapBetweenQuotedParagraphs() {
        let bmp = MarkdownRenderer(margin: 8).render("> 一つ目\n>\n> 二つ目")
        let single = MarkdownRenderer(margin: 8).render("> 一つ目")
        #expect(bmp.height > single.height * 2)
        #expect(fullyBlackColumns(bmp, in: 0..<40).count >= 4)
    }

    @Test func nestedQuotesDrawOneBarPerLevel() {
        let bmp = MarkdownRenderer(margin: 8).render("> > 内側")
        #expect(fullyBlackColumns(bmp, in: 0..<60).count >= 8)
    }

    @Test func horizontalRulesAreThickSolidLines() {
        let bmp = MarkdownRenderer(margin: 8).render("---")
        #expect(bmp.height >= 4)
        #expect(ruleRows(bmp).count >= 4)
        #expect(bmp.blackPixels(inColumns: 0..<8).isEmpty)
        #expect(bmp.blackPixels(inColumns: 360..<384).isEmpty)
    }

    @Test func tablesCollapseIntoCellBarCellRows() {
        #expect(MarkdownRenderer.plainText("| a | b |\n|---|---|\n| 1 | 2 |") == "a | b\n1 | 2")
    }

    @Test func codeBlocksUseTheMonospacedFontAndKeepIndentation() {
        let blocks = MarkdownRenderer(margin: 8).layout("```swift\n  let x = 1\n```")
        guard case .text(let runs) = blocks[0].content else {
            Issue.record("expected a text block")
            return
        }
        #expect(runs.map(\.text) == ["  let x = 1"])
        #expect(runs[0].style == .monospaced)
    }

    @Test func aSoftBreakBetweenJapaneseLinesAddsNoSpaceButBetweenWordsAddsOne() {
        #expect(MarkdownRenderer.plainText("日本語の\n文章") == "日本語の文章")
        #expect(MarkdownRenderer.plainText("hello\nworld") == "hello world")
        #expect(MarkdownRenderer.plainText("日本語\nabc") == "日本語 abc")
    }

    @Test func aHardBreakStartsANewLine() {
        #expect(MarkdownRenderer.plainText("一行目\\\n二行目") == "一行目\n二行目")
        #expect(MarkdownRenderer(margin: 8).wrappedLines("一行目\\\n二行目").flatMap { $0 } == ["一行目", "二行目"])
    }

    @Test func strikethroughKeepsItsText() {
        #expect(MarkdownRenderer.plainText("~~消す~~ と残す") == "消す と残す")
    }

    @Test func paragraphsAreSeparatedByAGap() {
        let one = MarkdownRenderer(margin: 8).render("あ")
        let two = MarkdownRenderer(margin: 8).render("あ\n\nあ")
        #expect(two.height > one.height * 2)
    }

    @Test func plainTextJoinsBlocksWithNewlines() {
        #expect(MarkdownRenderer.plainText("# 題\n\n本文\n\n- 項目") == "題\n本文\n項目")
    }

    @Test func emptyMarkdownRendersNothing() {
        #expect(MarkdownRenderer(margin: 8).render("").height == 0)
        #expect(MarkdownRenderer.plainText("") == "")
    }

    @Test func aFullMeetingMemoRendersWithoutOverflow() {
        let md = """
        # 10/24 打ち合わせメモ
        ## 決まったこと
        - **リリースは 11/15**
        - 検証環境は *来週月曜* から
        - 費用は前回見積もりのまま
        ## 宿題
        - [ ] 見積もり再提出（先方）
        - [ ] デザイン確認（自分）
        > 次回 10/31 14:00
        """
        let bmp = MarkdownRenderer(margin: 8).render(md)
        #expect(bmp.height > 200)
        #expect(bmp.blackPixels(inColumns: 0..<8).isEmpty)
        #expect(bmp.blackPixels(inColumns: 360..<384).isEmpty)
        #expect(ruleRows(bmp).count >= 6)
    }
}
