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

private func item(
    _ title: String = "牛乳を買う", list: String = "買い物",
    due: Date?, dueHasTime: Bool = true, notes: String? = nil, identifier: String? = nil
) -> ReminderItem {
    ReminderItem(title: title, list: list, due: due, dueHasTime: dueHasTime, notes: notes, identifier: identifier)
}

private let morning = date(2026, 10, 24, 9, 0)

private struct MarkingSummarizer: Summarizer {
    func summarize(_ text: String, kind: SummaryKind) async -> Summary {
        switch kind {
        case .heading: Summary(text: "見出し:" + text, usedModel: true)
        case .digest: Summary(text: "要約:" + text, usedModel: true)
        default: Summary(text: text, usedModel: true)
        }
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

private func card(_ item: ReminderItem, now: Date = morning, summarizer: any Summarizer = MarkingSummarizer()) async -> Card {
    await ReminderCard.make(item, now: now, calendar: tokyo, summarizer: summarizer)
}

private struct FakeStore: RemindersStore {
    let granted: Bool
    let items: [ReminderItem]
    let recorder: Recorder
    var lists: [String] = []

    final class Recorder: @unchecked Sendable {
        var fetchedStart: Date?
        var fetchCount = 0
    }

    func requestAccess() async throws -> Bool { granted }

    func listTitles() -> [String] { lists }

    func incompleteReminders(dueFrom start: Date) async -> [ReminderItem] {
        recorder.fetchedStart = start
        recorder.fetchCount += 1
        return items
    }
}

@Suite struct ReminderCardTests {
    @Test func reminderCardHasListAndDueInTheHeaderAndABallotBoxTitle() async {
        let card = await card(item(due: date(2026, 10, 24, 18, 0)))
        #expect(card.kind == .reminder)
        #expect(card.url == nil)
        #expect(card.header.lines == ["買い物"])
        #expect(card.header.sublines == ["期限 今日 18:00"])
        #expect(card.title == "☐ 牛乳を買う")
    }

    @Test func theQRIsTheDeepLinkToTheReminder() async {
        let card = await card(item(due: nil, identifier: "6F1B2C3D-0000-4000-8000-000000000001"))
        #expect(card.url == "x-apple-reminderkit://REMCDReminder/6F1B2C3D-0000-4000-8000-000000000001")
    }

    @Test func cardMatchesTheSharedReminderFixture() async throws {
        let notes = "低脂肪ではなく普通のもの。帰りにスーパーで。卵が安ければ一緒に。"
        let summarizer = FixedSummarizer(heading: "牛乳を買う", digest: notes)
        let reminder = item(due: date(2026, 10, 24, 18, 0), notes: notes, identifier: "6F1B2C3D-0000-4000-8000-000000000001")
        #expect(await card(reminder, summarizer: summarizer) == (try CardFixture.card("reminder")))
    }

    @Test func titleAndNotesAreHandedToTheSummarizerAndBecomeTheHeadingAndTheDigest() async {
        let long = "ryuzeeさんの新しい本の翻訳レビュワーとして本を通読する"
        let card = await card(item(long, due: nil, notes: "  第3章まで  "))
        #expect(card.title == "☐ 見出し:\(long)\n第3章まで")
        #expect(card.sections == [Card.Section(label: nil, text: "要約:\(long)\n第3章まで")])
        #expect(card.note == nil)
    }

    @Test func aLongTitleWithoutNotesIsSummarizedToo() async {
        let long = "ryuzeeさんの新しい本の翻訳レビュワーとして本を通読する"
        let card = await card(item(long, due: nil))
        #expect(card.title == "☐ 見出し:\(long)")
        #expect(card.sections == [Card.Section(label: nil, text: "要約:\(long)")])
    }

    @Test func aTitleThatFitsTheHeadingIsKeptAsIsAndNeverSummarized() async {
        let card = await card(item("牛乳を買う", due: nil))
        #expect(card.title == "☐ 牛乳を買う")
        #expect(card.sections.isEmpty)
    }

    @Test func shortNotesStayAsTheBodyWithoutALabel() async {
        let card = await card(item(due: nil, notes: "  帰りに寄る\n"))
        #expect(card.title == "☐ 牛乳を買う")
        #expect(card.sections == [Card.Section(label: nil, text: "帰りに寄る")])
    }

    @Test(arguments: [nil, "", "  \n "] as [String?])
    func absentOrBlankNotesLeaveNoSection(notes: String?) async {
        let card = await card(item(due: nil, notes: notes))
        #expect(card.sections.isEmpty)
    }

    @Test func summaryModelUnavailableTruncatesAndSaysSo() async {
        let long = "ryuzeeさんの新しい本の翻訳レビュワーとして本を通読する"
        let card = await card(item(long, due: nil), summarizer: TruncatingSummarizer())
        #expect(card.note == GitHubHandler.fallbackNote)
    }

    @Test func reminderWithoutADueDateHasNoDueLine() async {
        let card = await card(item(due: nil))
        #expect(card.header.sublines.isEmpty)
    }

    @Test func dateOnlyDueOmitsTheTime() async {
        let card = await card(item(due: date(2026, 10, 24), dueHasTime: false))
        #expect(card.header.sublines == ["期限 今日"])
    }

    @Test func timeIsZeroPadded() async {
        let card = await card(item(due: date(2026, 10, 24, 7, 5)))
        #expect(card.header.sublines == ["期限 今日 07:05"])
    }

    @Test func yesterdayAndTomorrowAreNamed() async {
        let yesterday = await card(item(due: date(2026, 10, 23, 18, 0)))
        let tomorrow = await card(item(due: date(2026, 10, 25, 18, 0)))
        #expect(yesterday.header.sublines == ["期限 昨日 18:00"])
        #expect(tomorrow.header.sublines == ["期限 明日 18:00"])
    }

    @Test func olderDueShowsDateAndWeekday() async {
        let card = await card(item(due: date(2026, 10, 20, 18, 0)))
        #expect(card.header.sublines == ["期限 10/20(火) 18:00"])
    }

    @Test func dueInAnotherYearShowsTheYear() async {
        let card = await card(item(due: date(2025, 12, 31, 18, 0)))
        #expect(card.header.sublines == ["期限 2025/12/31(水) 18:00"])
    }

    @Test func dueEarlierTodayThanNowIsStillToday() async {
        let card = await card(item(due: date(2026, 10, 24, 0, 30)), now: date(2026, 10, 24, 23, 0))
        #expect(card.header.sublines == ["期限 今日 00:30"])
    }

    @Test func todayAndLaterAreIncludedButOverdueAndNoDueAreNot() {
        let items = [
            item(due: date(2026, 10, 23, 8, 0)),
            item(due: date(2026, 10, 24, 18, 0)),
            item(due: date(2026, 10, 25, 8, 0)),
            item(due: nil),
        ]
        #expect(TodayFilter.reminders(items, now: morning, calendar: tokyo).count == 2)
    }

    @Test func aDateOnlyReminderDueTodayIsKeptEvenThoughItsDueIsTheStartOfToday() {
        let items = [item("日付のみ", due: date(2026, 10, 24), dueHasTime: false)]
        #expect(TodayFilter.reminders(items, now: morning, calendar: tokyo).map(\.title) == ["日付のみ"])
    }

    @Test func noListSelectionKeepsEveryReminder() {
        let items = [item("a", list: "仕事", due: nil), item("b", list: "買い物", due: nil)]
        #expect(TodayFilter.reminders(items, inList: nil) == items)
    }

    @Test func listSelectionKeepsOnlyThatListAndTheOrder() {
        let items = [
            item("a", list: "仕事", due: nil),
            item("b", list: "買い物", due: nil),
            item("c", list: "仕事", due: nil),
        ]
        #expect(TodayFilter.reminders(items, inList: "仕事").map(\.title) == ["a", "c"])
    }

    @Test func listsAreTheStoresListTitlesWithoutDuplicatesInNameOrder() async throws {
        let store = FakeStore(granted: true, items: [], recorder: .init(), lists: ["仕事", "買い物", "仕事", "家事"])
        let titles = try await RemindersSource(store: store, calendar: tokyo).lists()
        #expect(titles == titles.sorted())
        #expect(Set(titles) == ["仕事", "買い物", "家事"])
        #expect(titles.count == 3)
    }

    @Test func deniedAccessThrowsWhenReadingLists() async {
        let store = FakeStore(granted: false, items: [], recorder: .init(), lists: ["仕事"])
        await #expect(throws: RemindersSource.Failure.accessDenied) {
            try await RemindersSource(store: store, calendar: tokyo).lists()
        }
    }

    @Test func sourceAsksTheStoreForEverythingDueFromTheStartOfToday() async throws {
        let recorder = FakeStore.Recorder()
        let source = RemindersSource(store: FakeStore(granted: true, items: [], recorder: recorder), calendar: tokyo)
        _ = try await source.todaysReminders(now: morning)
        #expect(recorder.fetchedStart == date(2026, 10, 24, 0, 0))
    }

    @Test func sourceFiltersAgainAndOrdersWhatTheStoreReturns() async throws {
        let items = [
            item("明日の0時", due: date(2026, 10, 25, 0, 0)),
            item("夕方", due: date(2026, 10, 24, 18, 0)),
            item("期限なし", due: nil),
            item("昨日", due: date(2026, 10, 23, 9, 0)),
        ]
        let source = RemindersSource(store: FakeStore(granted: true, items: items, recorder: .init()), calendar: tokyo)
        #expect(try await source.todaysReminders(now: morning).map(\.title) == ["夕方", "明日の0時"])
    }

    @Test func sourceTurnsEachReminderIntoOneCard() async throws {
        let items = [item("明日", due: date(2026, 10, 25, 9, 0)), item("夕方", due: date(2026, 10, 24, 18, 0))]
        let source = RemindersSource(store: FakeStore(granted: true, items: items, recorder: .init()), calendar: tokyo)
        let cards = try await source.todaysCards(now: morning, summarizer: MarkingSummarizer())
        #expect(cards.map(\.title) == ["☐ 夕方", "☐ 明日"])
        #expect(cards.allSatisfy { $0.kind == .reminder })
    }

    @Test func deniedAccessThrowsWithoutFetching() async {
        let recorder = FakeStore.Recorder()
        let source = RemindersSource(store: FakeStore(granted: false, items: [item(due: nil)], recorder: recorder), calendar: tokyo)
        await #expect(throws: RemindersSource.Failure.accessDenied) {
            try await source.todaysReminders(now: morning)
        }
        #expect(recorder.fetchCount == 0)
    }

    @Test func renderedReminderCardKeepsInkInsideThePrintableWidth() async throws {
        let long = String(repeating: "「これは、長い題名。」（括弧）ー長音！？", count: 6)
        let urlLike = "https://example.com/" + String(repeating: "path/segment?q=abcdefghij&", count: 8)
        let reminder = item(
            long, list: long, due: date(2026, 10, 20, 18, 0), notes: urlLike + "\n" + long,
            identifier: "6F1B2C3D-0000-4000-8000-000000000001")
        let rendered = try CardRenderer(margin: 8).render(await card(reminder))
        #expect(rendered.bitmap.blackPixels(inColumns: 0..<8).isEmpty)
        #expect(rendered.bitmap.blackPixels(inColumns: 360..<384).isEmpty)
    }

    @Test func renderedReminderCardScansBackToTheDeepLink() async throws {
        let link = "x-apple-reminderkit://REMCDReminder/6F1B2C3D-0000-4000-8000-000000000001"
        let rendered = try CardRenderer().render(
            await card(item(due: date(2026, 10, 24, 18, 0), identifier: "6F1B2C3D-0000-4000-8000-000000000001")))
        let frame = try #require(rendered.qrFrame)
        var qrOnly = Bitmap1(height: frame.height)
        for y in 0..<frame.height {
            for x in 0..<frame.width where rendered.bitmap[x: frame.minX + x, y: frame.minY + y] {
                qrOnly.set(x: x, y: y)
            }
        }
        #expect(try QRDecoder.decode(qrOnly) == link)
    }
}
