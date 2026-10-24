import Foundation
import Synchronization
import Testing
@testable import ThermalPrinterCore

final class FakeGHRunner: ProcessRunner {
    private struct Calls {
        var executable: URL?
        var arguments: [String] = []
        var count = 0
    }

    private let calls = Mutex(Calls())
    private let outcome: ProcessOutcome?

    init(output: String, terminationStatus: Int32 = 0, truncated: Bool = false) {
        outcome = ProcessOutcome(terminationStatus: terminationStatus, output: output, truncated: truncated)
    }

    init(stdoutFixture: String) {
        outcome = ProcessOutcome(terminationStatus: 0, output: (try? gitHubFixtureText(stdoutFixture)) ?? "")
    }

    init(throwing: Bool) {
        outcome = nil
    }

    var lastExecutable: URL? { calls.withLock { $0.executable } }
    var lastArguments: [String] { calls.withLock { $0.arguments } }
    var callCount: Int { calls.withLock { $0.count } }

    func run(executable: URL, arguments: [String]) async throws -> ProcessOutcome {
        calls.withLock {
            $0.executable = executable
            $0.arguments = arguments
            $0.count += 1
        }
        guard let outcome else { throw CocoaError(.fileNoSuchFile) }
        return outcome
    }
}

final class RecordingSummarizer: Summarizer {
    private let seen = Mutex<[SummaryKind: String]>([:])

    func input(for kind: SummaryKind) -> String? { seen.withLock { $0[kind] } }

    func summarize(_ text: String, kind: SummaryKind) async -> Summary {
        seen.withLock { $0[kind] = text }
        return Summary(text: "要約", usedModel: true)
    }
}

struct EchoSummarizer: Summarizer {
    func summarize(_ text: String, kind: SummaryKind) async -> Summary {
        Summary(text: text, usedModel: true)
    }
}

func gitHubFixtureText(_ name: String) throws -> String {
    let dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    return try String(contentsOf: dir.appending(path: "Fixtures/\(name)"), encoding: .utf8)
}

private func isoDate(_ text: String) -> Date {
    ISO8601DateFormatter().date(from: text)!
}

private let fixedNow: @Sendable () -> Date = { isoDate("2026-10-24T09:30:00Z") }
private let presentGH = GHLocator(isExecutable: { _ in true })
private let absentGH = GHLocator(isExecutable: { _ in false })
private let issueURL = URL(string: "https://github.com/bash0C7/thermal-printer/issues/1")!

private func handler(
    fixture: String, summarizer: any Summarizer = TruncatingSummarizer()
) -> (GitHubHandler, FakeGHRunner) {
    let runner = FakeGHRunner(stdoutFixture: fixture)
    return (GitHubHandler(runner: runner, summarizer: summarizer, locator: presentGH, now: fixedNow), runner)
}

private func failingHandler(output: String, status: Int32 = 1) -> (GitHubHandler, FakeGHRunner) {
    let runner = FakeGHRunner(output: output, terminationStatus: status)
    return (GitHubHandler(runner: runner, summarizer: TruncatingSummarizer(), locator: presentGH, now: fixedNow), runner)
}

@Test func githubIssueBecomesACardWithRepoNumberAndSummaries() async throws {
    let (h, _) = handler(fixture: "gh-issue-with-comments.json")
    let card = try await h.card(for: URL(string: "https://github.com/bash0C7/thermal-printer/issues/12")!)
    #expect(card.kind == .github)
    #expect(card.url == "https://github.com/bash0C7/thermal-printer/issues/12")
    #expect(card.header.lines == ["bash0C7/thermal-printer"])
    #expect(card.header.emphasis == "#12")
    #expect(card.title == "長い出力のときに GUI で警告を出す")
    #expect(card.sections.map(\.label) == [nil, "最新コメント"])
}

@Test func headerSublineShowsStateAndRelativeUpdateTime() async throws {
    let (h, _) = handler(fixture: "gh-issue-with-comments.json")
    let card = try await h.card(for: URL(string: "https://github.com/bash0C7/thermal-printer/issues/12")!)
    #expect(card.header.sublines == ["open ・ 更新 2日前"])
}

@Test func overviewIsTheSummaryAndTheLatestCommentCarriesItsRelativeDate() async throws {
    let (h, _) = handler(fixture: "gh-issue-with-comments.json", summarizer: EchoSummarizer())
    let card = try await h.card(for: URL(string: "https://github.com/bash0C7/thermal-printer/issues/12")!)
    #expect(card.sections[0].text.hasPrefix("印字長が閾値を超えたら"))
    #expect(card.sections[1].text == "2日前: 閾値は 50cm でもよいかも。ロール 1 本の長さも考慮したい。")
    #expect(card.note == nil)
}

@Test func issueWithoutCommentsHasNoLatestCommentSection() async throws {
    let (h, _) = handler(fixture: "gh-issue-no-comments.json")
    let card = try await h.card(for: issueURL)
    #expect(card.sections.count == 1)
    #expect(card.sections[0].label == nil)
}

@Test func realIssueOneBecomesAGitHubCard() async throws {
    let (h, _) = handler(fixture: "gh-issue-no-comments.json")
    let card = try await h.card(for: issueURL)
    #expect(card.kind == .github)
    #expect(card.header.lines == ["bash0C7/thermal-printer"])
    #expect(card.header.emphasis == "#1")
    #expect(card.url == issueURL.absoluteString)
}

@Test func truncationFallbackLeavesANoteOnTheCard() async throws {
    let (h, _) = handler(fixture: "gh-issue-with-comments.json")
    let card = try await h.card(for: URL(string: "https://github.com/bash0C7/thermal-printer/issues/12")!)
    #expect(card.note?.contains("切り詰め") == true)
}

@Test func pullRequestURLUsesGhPrView() async throws {
    let (h, runner) = handler(fixture: "gh-pr.json")
    let card = try await h.card(for: URL(string: "https://github.com/bash0C7/thermal-printer/pull/2")!)
    #expect(runner.lastArguments.prefix(3) == ["pr", "view", "2"])
    #expect(card.kind == .github)
    #expect(card.header.emphasis == "#2")
    #expect(card.header.sublines == ["merged ・ 更新 3日前"])
}

@Test func issueURLUsesGhIssueViewWithTheRepoAndNoWriteVerbs() async throws {
    let (h, runner) = handler(fixture: "gh-issue-no-comments.json")
    _ = try await h.card(for: issueURL)
    #expect(runner.lastArguments.prefix(5) == ["issue", "view", "1", "-R", "bash0C7/thermal-printer"])
    #expect(runner.lastArguments.contains("--json"))
    #expect(runner.lastExecutable == URL(filePath: "/opt/homebrew/bin/gh"))
}

@Test func summariesReceiveAtMostTheHeadOfTheBodyAndOfTheLatestComment() async throws {
    let long = String(repeating: "あ", count: 10000)
    let json = try JSONSerialization.data(withJSONObject: [
        "title": "長い", "state": "OPEN", "updatedAt": "2026-10-24T09:00:00Z", "url": issueURL.absoluteString,
        "body": long, "comments": [["body": long, "createdAt": "2026-10-24T09:00:00Z"]],
    ])
    let runner = FakeGHRunner(output: String(decoding: json, as: UTF8.self))
    let recorder = RecordingSummarizer()
    let h = GitHubHandler(runner: runner, summarizer: recorder, locator: presentGH, now: fixedNow)
    _ = try await h.card(for: issueURL)
    #expect(recorder.input(for: .overview)?.count == 4000)
    #expect(recorder.input(for: .comment)?.count == 2000)
}

@Test func ghIsAskedForTheWholeJSONWithoutAJqFilter() async throws {
    let (h, runner) = handler(fixture: "gh-issue-no-comments.json")
    _ = try await h.card(for: issueURL)
    #expect(!runner.lastArguments.contains("--jq"))
    #expect(runner.lastArguments.suffix(2) == ["--json", "title,body,state,updatedAt,comments,url"])
}

@Test func outputCutByTheRunnerFallsBackWithAReason() async throws {
    let runner = FakeGHRunner(output: "{\"title\":\"x\"}", truncated: true)
    let h = GitHubHandler(runner: runner, summarizer: TruncatingSummarizer(), locator: presentGH, now: fixedNow)
    let card = try await h.card(for: issueURL)
    #expect(card.kind == .url)
    #expect(card.note?.contains("大きすぎます") == true)
}

@Test func ghFailureFallsBackToTheUnknownURLCardWithAReason() async throws {
    let (h, _) = failingHandler(output: "HTTP 404: Not Found")
    let card = try await h.card(for: issueURL)
    #expect(card.kind == .url)
    #expect(card.url == issueURL.absoluteString)
    #expect(card.title == issueURL.absoluteString)
    #expect(card.note?.contains("取得できません") == true)
    #expect(card.note?.contains("HTTP 404") == true)
}

@Test func missingGhFallsBackWithoutRunningAnything() async throws {
    let runner = FakeGHRunner(stdoutFixture: "gh-issue-no-comments.json")
    let h = GitHubHandler(runner: runner, summarizer: TruncatingSummarizer(), locator: absentGH, now: fixedNow)
    let card = try await h.card(for: issueURL)
    #expect(card.kind == .url)
    #expect(card.note?.contains("取得できません") == true)
    #expect(runner.callCount == 0)
}

@Test func unreadableGhOutputFallsBackToTheUnknownURLCard() async throws {
    let (h, _) = failingHandler(output: "{\"title\": \"途中で切れた", status: 0)
    let card = try await h.card(for: issueURL)
    #expect(card.kind == .url)
    #expect(card.note?.contains("取得できません") == true)
}

@Test func runnerErrorFallsBackToTheUnknownURLCard() async throws {
    let h = GitHubHandler(runner: FakeGHRunner(throwing: true), summarizer: TruncatingSummarizer(), locator: presentGH, now: fixedNow)
    let card = try await h.card(for: issueURL)
    #expect(card.kind == .url)
    #expect(card.note?.contains("取得できません") == true)
}

@Test(arguments: [
    "https://github.com/bash0C7/thermal-printer/issues/1",
    "https://github.com/bash0C7/thermal-printer/pull/2",
    "https://github.com/bash0C7/thermal-printer/pull/2/files",
    "https://github.com/bash0C7/thermal-printer/issues/1#issuecomment-123",
    "https://www.github.com/bash0C7/thermal-printer/issues/1",
])
func githubIssueAndPullURLsAreHandled(string: String) throws {
    let (h, _) = handler(fixture: "gh-pr.json")
    #expect(h.handles(try #require(URL(string: string))))
}

@Test(arguments: [
    "https://github.com/bash0C7/thermal-printer",
    "https://github.com/bash0C7/thermal-printer/issues",
    "https://github.com/bash0C7/thermal-printer/issues/new",
    "https://github.com/bash0C7/thermal-printer/blob/main/README.md",
    "https://github.com/-evil/thermal-printer/issues/1",
    "https://example.com/bash0C7/thermal-printer/issues/1",
    "http://github.com/bash0C7/thermal-printer/issues/1",
])
func otherURLsAreNotHandledByGitHub(string: String) throws {
    let (h, _) = handler(fixture: "gh-pr.json")
    #expect(!h.handles(try #require(URL(string: string))))
}

@Test func locatorPrefersHomebrewThenUsrLocal() {
    let both = GHLocator(isExecutable: { _ in true })
    #expect(both.locate() == URL(filePath: "/opt/homebrew/bin/gh"))
    let onlyUsrLocal = GHLocator(isExecutable: { $0 == "/usr/local/bin/gh" })
    #expect(onlyUsrLocal.locate() == URL(filePath: "/usr/local/bin/gh"))
    #expect(GHLocator(isExecutable: { _ in false }).locate() == nil)
}

private struct RelativeCase: Sendable, CustomTestStringConvertible {
    let seconds: Double
    let expected: String
    var testDescription: String { "\(seconds)s -> \(expected)" }
}

private let day: Double = 86400

private let relativeCases: [RelativeCase] = [
    RelativeCase(seconds: 0, expected: "たった今"),
    RelativeCase(seconds: 59, expected: "たった今"),
    RelativeCase(seconds: 60, expected: "1分前"),
    RelativeCase(seconds: 3599, expected: "59分前"),
    RelativeCase(seconds: 3600, expected: "1時間前"),
    RelativeCase(seconds: 86399, expected: "23時間前"),
    RelativeCase(seconds: day, expected: "1日前"),
    RelativeCase(seconds: 2 * day, expected: "2日前"),
    RelativeCase(seconds: 29 * day, expected: "29日前"),
    RelativeCase(seconds: 30 * day, expected: "1か月前"),
    RelativeCase(seconds: 364 * day, expected: "12か月前"),
    RelativeCase(seconds: 365 * day, expected: "1年前"),
    RelativeCase(seconds: 800 * day, expected: "2年前"),
    RelativeCase(seconds: -120, expected: "たった今"),
]

@Test(arguments: relativeCases)
private func relativeDateIsWrittenInJapanese(item: RelativeCase) {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    #expect(RelativeDate.text(from: now.addingTimeInterval(-item.seconds), now: now) == item.expected)
}
