import Foundation
import Testing
@testable import ThermalPrinterCore

private let article = """
<!doctype html><html lang="ja"><head><meta charset="utf-8"><title> ロール紙の
 長さについて &amp; 印字 </title>
<style>body { color: red }</style><script>var secret = "ignored";</script></head>
<body><nav>menu</nav><h1>ロール紙の長さ</h1>
<p>感熱ロール紙は&nbsp;1本で約&#51;mの長さがあり、&lt;切り取り&gt;位置は&#x30D8;ッドの先です。</p>
<!-- hidden comment --><p>二つ目の段落です。<br>改行も扱います。</p></body></html>
"""

private let pageURL = URL(string: "https://example.com/articles/roll")!

private func handler(
    runner: FakeGHRunner, summarizer: any Summarizer = EchoSummarizer()
) -> WebPageHandler {
    WebPageHandler(runner: runner, summarizer: summarizer)
}

@Test func titleIsReadAndWhitespaceAndEntitiesAreNormalised() {
    #expect(HTMLText.extract(article).title == "ロール紙の 長さについて & 印字")
}

@Test func scriptsStylesAndCommentsAreDroppedFromTheBody() {
    let body = HTMLText.extract(article).body
    #expect(!body.contains("secret"))
    #expect(!body.contains("color: red"))
    #expect(!body.contains("hidden comment"))
    #expect(!body.contains("ロール紙の 長さについて"))
}

@Test func blockTagsBecomeLinesAndEntitiesAreDecoded() {
    let lines = HTMLText.extract(article).body.split(separator: "\n").map(String.init)
    #expect(lines.contains("ロール紙の長さ"))
    #expect(lines.contains("感熱ロール紙は 1本で約3mの長さがあり、<切り取り>位置はヘッドの先です。"))
    #expect(lines.contains("二つ目の段落です。"))
    #expect(lines.contains("改行も扱います。"))
}

@Test func unknownEntitiesAreLeftAsTheyAre() {
    #expect(HTMLText.extract("<p>a &unknown; b</p>").body == "a &unknown; b")
}

@Test func pageWithoutTitleHasNilTitle() {
    #expect(HTMLText.extract("<p>本文だけ</p>").title == nil)
}

@Test func webPageBecomesAUrlCardWithTitleHostQRAndSummary() async throws {
    let runner = FakeGHRunner(output: article)
    let card = try await handler(runner: runner).card(for: pageURL)
    #expect(card.kind == .url)
    #expect(card.url == pageURL.absoluteString)
    #expect(card.header.lines == ["example.com"])
    #expect(card.title == "ロール紙の 長さについて & 印字")
    #expect(card.sections.count == 1)
    #expect(card.sections[0].text.contains("二つ目の段落です。"))
    #expect(card.note == nil)
}

@Test func curlIsRunWithBoundedTimeProtocolsAndTheURLAsTheLastArgument() async throws {
    let runner = FakeGHRunner(output: article)
    _ = try await handler(runner: runner).card(for: pageURL)
    #expect(runner.lastExecutable?.path == "/usr/bin/curl")
    #expect(runner.lastArguments.last == pageURL.absoluteString)
    #expect(runner.lastArguments.contains("--max-time"))
    #expect(runner.lastArguments.contains("--max-filesize"))
    #expect(runner.lastArguments.contains("=http,https"))
}

@Test func titlelessPageGetsAGeneratedHeading() async throws {
    let runner = FakeGHRunner(output: "<p>題名の無いページですが、本文はちゃんと二十文字以上あります。</p>")
    let card = try await handler(runner: runner).card(for: pageURL)
    #expect(card.title.hasPrefix("題名の無いページ"))
}

@Test func truncationFallbackIsNotedOnTheCard() async throws {
    let runner = FakeGHRunner(output: article)
    let card = try await handler(runner: runner, summarizer: TruncatingSummarizer()).card(for: pageURL)
    #expect(card.note == GitHubHandler.fallbackNote)
}

@Test func curlFailureThrowsWithTheFirstLineOfItsMessage() async {
    let runner = FakeGHRunner(output: "curl: (6) Could not resolve host\nmore", terminationStatus: 6)
    await #expect(throws: WebPageHandler.Failure.fetchFailed("curl: (6) Could not resolve host")) {
        try await handler(runner: runner).card(for: pageURL)
    }
}

@Test func pageWithoutReadableTextThrows() async {
    let runner = FakeGHRunner(output: "<html><script>only()</script></html>")
    await #expect(throws: WebPageHandler.Failure.noText) {
        try await handler(runner: runner).card(for: pageURL)
    }
}

@Test func onlyHttpAndHttpsAreHandled() {
    let web = handler(runner: FakeGHRunner(output: ""))
    #expect(web.handles(URL(string: "http://example.com")!))
    #expect(web.handles(URL(string: "https://example.com")!))
    #expect(!web.handles(URL(string: "file:///etc/passwd")!))
    #expect(!web.handles(URL(string: "ftp://example.com/a")!))
}
