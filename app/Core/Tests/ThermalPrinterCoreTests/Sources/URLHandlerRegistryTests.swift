import Foundation
import Testing
@testable import ThermalPrinterCore

private struct StubHandler: URLHandler {
    let host: String
    var fails = false

    func handles(_ url: URL) -> Bool { url.host() == host }

    func card(for url: URL) async throws -> Card {
        if fails { throw CocoaError(.fileReadUnknown) }
        return Card(kind: .github, url: url.absoluteString, header: .init(lines: ["stub"]), title: "stub")
    }
}

private let standard = URLHandlerRegistry.standard(
    runner: FakeGHRunner(stdoutFixture: "gh-issue-no-comments.json"),
    summarizer: TruncatingSummarizer(),
    locator: GHLocator(isExecutable: { _ in true }),
    now: { Date(timeIntervalSince1970: 1_792_834_200) }
)

@Test func githubURLIsRoutedToTheGitHubHandler() async throws {
    let card = await standard.card(for: URL(string: "https://github.com/bash0C7/thermal-printer/issues/1")!)
    #expect(card.kind == .github)
}

@Test func slackPermalinkIsRoutedToTheSlackHandlerWithoutRunningGh() async throws {
    let runner = FakeGHRunner(stdoutFixture: "gh-issue-no-comments.json")
    let registry = URLHandlerRegistry.standard(
        runner: runner, summarizer: TruncatingSummarizer(), locator: GHLocator(isExecutable: { _ in true }), now: { Date() })
    let card = await registry.card(for: URL(string: "https://example.slack.com/archives/C0123456789/p1792565843307099")!)
    #expect(card.kind == .slack)
    #expect(runner.callCount == 0)
}

@Test func unknownURLBecomesAUrlCardWithTheHostTheFullURLAndNoNote() async throws {
    let text = "https://example.com/articles/2026/10/roll-length?utm_source=newsletter&ref=abcdefghijklmnopqrstuvwxyz0123456789"
    let card = await standard.card(for: URL(string: text)!)
    #expect(card.kind == .url)
    #expect(card.url == text)
    #expect(card.title == text)
    #expect(card.header.lines == ["example.com"])
    #expect(card.header.emphasis == nil)
    #expect(card.sections.isEmpty)
    #expect(card.note == nil)
}

@Test func handlersAreTriedInRegistrationOrder() async throws {
    let registry = URLHandlerRegistry(handlers: [StubHandler(host: "a.example"), StubHandler(host: "b.example")])
    #expect(await registry.card(for: URL(string: "https://a.example/x")!).kind == .github)
    #expect(await registry.card(for: URL(string: "https://c.example/x")!).kind == .url)
}

@Test func aHandlerThatThrowsFallsBackToTheUnknownURLCardWithAReason() async throws {
    let registry = URLHandlerRegistry(handlers: [StubHandler(host: "a.example", fails: true)])
    let card = await registry.card(for: URL(string: "https://a.example/x")!)
    #expect(card.kind == .url)
    #expect(card.note?.contains("取得できません") == true)
}

@Test func unknownURLHandlerHandlesEverything() throws {
    #expect(UnknownURLHandler().handles(try #require(URL(string: "mailto:a@example.com"))))
}

@Test func unknownURLCardsEncodeToTheSharedCardSchema() async throws {
    let card = await standard.card(for: URL(string: "https://example.com/a")!)
    let decoded = try JSONDecoder().decode(Card.self, from: JSONEncoder().encode(card))
    #expect(decoded == card)
}
