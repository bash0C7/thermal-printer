import Testing
@testable import ThermalPrinterCore

@Test func truncationKeepsTheHeadAndAddsAnEllipsis() async {
    let s = await TruncatingSummarizer().summarize(String(repeating: "あ", count: 200), kind: .overview)
    #expect(s.text == String(repeating: "あ", count: 60) + "…")
    #expect(s.usedModel == false)
}

@Test func shortTextIsNotEllipsized() async {
    #expect(await TruncatingSummarizer().summarize("短い", kind: .overview).text == "短い")
}

@Test func textOfExactlyTheLimitIsNotEllipsized() async {
    let text = String(repeating: "い", count: 60)
    #expect(await TruncatingSummarizer().summarize(text, kind: .overview).text == text)
}

@Test func commentKindKeepsFortyCharacters() async {
    let s = await TruncatingSummarizer().summarize(String(repeating: "う", count: 100), kind: .comment)
    #expect(s.text == String(repeating: "う", count: 40) + "…")
}

@Test func whitespaceRunsAndNewlinesCollapseToOneSpace() async {
    let s = await TruncatingSummarizer().summarize("  一行目\n\n\n二行目\r\n  三行目  ", kind: .overview)
    #expect(s.text == "一行目 二行目 三行目")
}

@Test func blankTextGivesAnEmptySummary() async {
    let s = await TruncatingSummarizer().summarize(" \n\t ", kind: .comment)
    #expect(s.text.isEmpty)
    #expect(s.usedModel == false)
}

@Test func graphemeClustersAreNotSplit() async {
    let family = "👨‍👩‍👧"
    let s = await TruncatingSummarizer().summarize(String(repeating: family, count: 100), kind: .comment)
    #expect(s.text == String(repeating: family, count: 40) + "…")
}

@Test func modelOutputKeepsAtMostTheLineLimit() {
    #expect(SummaryKind.overview.fit("一\n二\n三\n四") == "一\n二\n三")
    #expect(SummaryKind.comment.fit("一\n二\n三") == "一\n二")
}

@Test func modelOutputDropsBlankLinesAndOuterWhitespace() {
    #expect(SummaryKind.overview.fit("\n  一行目  \n\n 二行目\n") == "一行目\n二行目")
}

@Test func modelOutputLongerThanOneAndAHalfTimesTheTargetIsEllipsized() {
    let fitted = SummaryKind.overview.fit(String(repeating: "あ", count: 200))
    #expect(fitted == String(repeating: "あ", count: 90) + "…")
}

@Test func modelOutputWithinTheHardLimitIsKept() {
    let text = String(repeating: "あ", count: 90)
    #expect(SummaryKind.overview.fit(text) == text)
}

@Test func headingKeepsTwentyCharactersOnOneLine() async {
    let s = await TruncatingSummarizer().summarize(String(repeating: "え", count: 50), kind: .heading)
    #expect(s.text == String(repeating: "え", count: 20) + "…")
    #expect(SummaryKind.heading.fit("一\n二") == "一")
}

@Test func digestKeepsOneHundredTwentyCharactersAndFiveLines() async {
    let s = await TruncatingSummarizer().summarize(String(repeating: "お", count: 300), kind: .digest)
    #expect(s.text == String(repeating: "お", count: 120) + "…")
    #expect(SummaryKind.digest.fit("1\n2\n3\n4\n5\n6") == "1\n2\n3\n4\n5")
}

@Test func promptsForFreeTextDoNotMentionGitHub() {
    for kind in [SummaryKind.heading, .digest] {
        #expect(!FoundationModelSummarizer.prompt("本文", kind: kind).contains("GitHub"))
        #expect(!FoundationModelSummarizer.instructions(for: kind).contains("GitHub"))
    }
}
