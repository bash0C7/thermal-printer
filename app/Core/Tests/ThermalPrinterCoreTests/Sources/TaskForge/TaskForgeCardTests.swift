import Foundation
import Testing
@testable import ThermalPrinterCore

private let tokyo: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
    return calendar
}()

private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
    tokyo.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
}

private let morning = date(2026, 10, 24, 9, 0)

private func task(
    _ title: String = "期限つき", relativePath: String? = nil, status: String = "open",
    due: Date? = nil, dueHasTime: Bool = false, scheduled: Date? = nil, scheduledHasTime: Bool = false,
    projects: [String] = [], stableID: String? = nil, body: String = ""
) -> TaskNote {
    TaskNote(
        title: title, relativePath: relativePath ?? "00_TaskNotes/\(title).md", status: status, priority: nil,
        due: due, dueHasTime: dueHasTime, scheduled: scheduled, scheduledHasTime: scheduledHasTime,
        projects: projects, stableID: stableID, body: body)
}

private struct Passthrough: Summarizer {
    func summarize(_ text: String, kind: SummaryKind) async -> Summary {
        Summary(text: text, usedModel: true)
    }
}

private struct FixedSummarizer: Summarizer {
    let heading: String
    let digest: String

    func summarize(_ text: String, kind: SummaryKind) async -> Summary {
        switch kind {
        case .heading: Summary(text: heading, usedModel: true)
        case .digest: Summary(text: digest, usedModel: true)
        default: Summary(text: text, usedModel: true)
        }
    }
}

private func card(_ note: TaskNote, summarizer: any Summarizer = Passthrough()) async -> Card {
    await TaskForgeCard.make(note, vaultName: "my-vault", now: morning, calendar: tokyo, summarizer: summarizer)
}

@Test func aTaskWithAStableIDLinksToTaskForge() {
    #expect(TaskForgeLink.url(for: task(stableID: "weekly-report"), vaultName: "my-vault")
        == "taskforge:///task/weekly-report")
}

@Test func aTaskWithoutAStableIDLinksToItsFileInObsidian() {
    #expect(TaskForgeLink.url(for: task(relativePath: "00_TaskNotes/a & b+c #1?.md"), vaultName: "my-vault")
        == "obsidian://open?vault=my-vault&file=00_TaskNotes%2Fa%20%26%20b%2Bc%20%231%3F")
}

@Test func theCardCarriesProjectsStatusDatesAndACheckbox() async {
    let card = await card(task(
        status: "planned", due: date(2026, 10, 25), scheduled: date(2026, 10, 24, 9, 0), scheduledHasTime: true,
        projects: ["Sample Project"]))
    #expect(card.kind == .task)
    #expect(card.header.lines == ["Sample Project"])
    #expect(card.header.emphasis == "planned")
    #expect(card.header.sublines == ["予定 今日 09:00", "期限 明日"])
    #expect(card.title == "☐ 期限つき")
}

@Test func projectsAreJoinedAndAnAbsentProjectFallsBackToTaskForge() async {
    let two = await card(task(projects: ["Sample Project", "Blog"]))
    let none = await card(task())
    #expect(two.header.lines == ["Sample Project ・ Blog"])
    #expect(none.header.lines == ["TaskForge"])
}

@Test func onlyTheDatesThatExistAreListed() async {
    let scheduledOnly = await card(task(scheduled: date(2026, 10, 24)))
    let dueOnly = await card(task(due: date(2026, 10, 23)))
    let neither = await card(task())
    #expect(scheduledOnly.header.sublines == ["予定 今日"])
    #expect(dueOnly.header.sublines == ["期限 昨日"])
    #expect(neither.header.sublines.isEmpty)
}

@Test func aShortBodyStaysAsTheBodyAndIsNeverSummarized() async {
    let card = await card(task(body: "週次報告を出す。"))
    #expect(card.title == "☐ 期限つき")
    #expect(card.sections == [Card.Section(label: nil, text: "週次報告を出す。")])
    #expect(card.note == nil)
}

@Test func aTaskWithoutABodyHasNoSection() async {
    #expect(await card(task()).sections.isEmpty)
}

@Test func aLongTaskIsSummarized() async {
    let body = "sampleさんの新しい本の翻訳レビュワーとして本を通読する。第3章まで読んだ。"
    let summarizer = FixedSummarizer(heading: "本を通読する", digest: "第3章まで")
    let card = await card(task("翻訳レビュー", body: body), summarizer: summarizer)
    #expect(card.title == "☐ 本を通読する")
    #expect(card.sections == [Card.Section(label: nil, text: "第3章まで")])
}

@Test func summaryModelUnavailableTruncatesAndSaysSo() async {
    let card = await card(task("翻訳レビュー", body: String(repeating: "長い本文", count: 30)), summarizer: TruncatingSummarizer())
    #expect(card.note == GitHubHandler.fallbackNote)
}

@Test func everyFixtureTaskCardRendersAndItsQRReadsBackToItsLink() async throws {
    for note in try TaskForgeSource.openTasks(vault: fixtureVault) {
        let card = await TaskForgeCard.make(note, vaultName: "my-vault", now: morning, summarizer: Passthrough())
        let rendered = try CardRenderer().render(card)
        #expect(try QRReader.payloads(in: #require(rendered.bitmap.cgImage())) == [card.url!])
    }
}

@Test func aLinkTooLongForTheQRIsLeftOutWithANote() async {
    let card = await card(task(relativePath: "00_TaskNotes/" + String(repeating: "長", count: 400) + ".md"))
    #expect(card.url == nil)
    #expect(card.note == TaskForgeCard.qrOmittedNote)
}
