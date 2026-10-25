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
    due: Date?, dueHasTime: Bool = true, notes: String? = nil
) -> ReminderItem {
    ReminderItem(title: title, list: list, due: due, dueHasTime: dueHasTime, notes: notes)
}

private let morning = date(2026, 10, 24, 9, 0)

private struct FakeStore: RemindersStore {
    let granted: Bool
    let items: [ReminderItem]
    let recorder: Recorder

    final class Recorder: @unchecked Sendable {
        var fetchedStart: Date?
        var fetchCount = 0
    }

    func requestAccess() async throws -> Bool { granted }

    func incompleteReminders(dueFrom start: Date) async -> [ReminderItem] {
        recorder.fetchedStart = start
        recorder.fetchCount += 1
        return items
    }
}

@Suite struct ReminderCardTests {
    @Test func reminderCardHasListAndDueInTheHeaderAndABallotBoxTitle() {
        let card = ReminderCard.make(item(due: date(2026, 10, 24, 18, 0)), now: morning, calendar: tokyo)
        #expect(card.kind == .reminder)
        #expect(card.url == nil)
        #expect(card.header.lines == ["買い物"])
        #expect(card.header.sublines == ["期限 今日 18:00"])
        #expect(card.title == "☐ 牛乳を買う")
    }

    @Test func cardMatchesTheSharedReminderFixture() throws {
        let notes = "低脂肪ではなく普通のもの。帰りにスーパーで。卵が安ければ一緒に。"
        let card = ReminderCard.make(item(due: date(2026, 10, 24, 18, 0), notes: notes), now: morning, calendar: tokyo)
        #expect(card == (try CardFixture.card("reminder")))
    }

    @Test func notesBecomeTheBodySectionWithoutALabel() {
        let card = ReminderCard.make(item(due: nil, notes: "  帰りに寄る\n"), now: morning, calendar: tokyo)
        #expect(card.sections == [Card.Section(label: nil, text: "帰りに寄る")])
    }

    @Test(arguments: [nil, "", "  \n "] as [String?])
    func absentOrBlankNotesLeaveNoSection(notes: String?) {
        let card = ReminderCard.make(item(due: nil, notes: notes), now: morning, calendar: tokyo)
        #expect(card.sections.isEmpty)
    }

    @Test func reminderWithoutADueDateHasNoDueLine() {
        let card = ReminderCard.make(item(due: nil), now: morning, calendar: tokyo)
        #expect(card.header.sublines.isEmpty)
    }

    @Test func dateOnlyDueOmitsTheTime() {
        let card = ReminderCard.make(item(due: date(2026, 10, 24), dueHasTime: false), now: morning, calendar: tokyo)
        #expect(card.header.sublines == ["期限 今日"])
    }

    @Test func timeIsZeroPadded() {
        let card = ReminderCard.make(item(due: date(2026, 10, 24, 7, 5)), now: morning, calendar: tokyo)
        #expect(card.header.sublines == ["期限 今日 07:05"])
    }

    @Test func yesterdayAndTomorrowAreNamed() {
        let yesterday = ReminderCard.make(item(due: date(2026, 10, 23, 18, 0)), now: morning, calendar: tokyo)
        let tomorrow = ReminderCard.make(item(due: date(2026, 10, 25, 18, 0)), now: morning, calendar: tokyo)
        #expect(yesterday.header.sublines == ["期限 昨日 18:00"])
        #expect(tomorrow.header.sublines == ["期限 明日 18:00"])
    }

    @Test func olderDueShowsDateAndWeekday() {
        let card = ReminderCard.make(item(due: date(2026, 10, 20, 18, 0)), now: morning, calendar: tokyo)
        #expect(card.header.sublines == ["期限 10/20(火) 18:00"])
    }

    @Test func dueInAnotherYearShowsTheYear() {
        let card = ReminderCard.make(item(due: date(2025, 12, 31, 18, 0)), now: morning, calendar: tokyo)
        #expect(card.header.sublines == ["期限 2025/12/31(水) 18:00"])
    }

    @Test func dueEarlierTodayThanNowIsStillToday() {
        let card = ReminderCard.make(item(due: date(2026, 10, 24, 0, 30)), now: date(2026, 10, 24, 23, 0), calendar: tokyo)
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
        let cards = try await source.todaysCards(now: morning)
        #expect(cards.map(\.title) == ["☐ 夕方", "☐ 明日"])
        #expect(cards.allSatisfy { $0.kind == .reminder && $0.url == nil })
    }

    @Test func deniedAccessThrowsWithoutFetching() async {
        let recorder = FakeStore.Recorder()
        let source = RemindersSource(store: FakeStore(granted: false, items: [item(due: nil)], recorder: recorder), calendar: tokyo)
        await #expect(throws: RemindersSource.Failure.accessDenied) {
            try await source.todaysReminders(now: morning)
        }
        #expect(recorder.fetchCount == 0)
    }

    @Test func renderedReminderCardHasNoQRAndKeepsInkInsideThePrintableWidth() throws {
        let long = String(repeating: "「これは、長い題名。」（括弧）ー長音！？", count: 6)
        let urlLike = "https://example.com/" + String(repeating: "path/segment?q=abcdefghij&", count: 8)
        let card = ReminderCard.make(
            item(long, list: long, due: date(2026, 10, 20, 18, 0), notes: urlLike + "\n" + long),
            now: morning, calendar: tokyo
        )
        let rendered = try CardRenderer(margin: 8).render(card)
        #expect(rendered.qrFrame == nil)
        #expect(rendered.bitmap.blackPixels(inColumns: 0..<8).isEmpty)
        #expect(rendered.bitmap.blackPixels(inColumns: 360..<384).isEmpty)
    }
}
