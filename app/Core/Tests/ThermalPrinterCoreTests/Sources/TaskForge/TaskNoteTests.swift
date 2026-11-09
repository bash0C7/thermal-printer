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

private func parse(_ path: String) throws -> TaskNote? {
    TaskNote.parse(relativePath: path, contents: try taskForgeFixture(path), dialect: .standard, calendar: tokyo)
}

@Test func aTaskFileYieldsItsTitleStatusProjectsAndBody() throws {
    let path = "00_TaskNotes/週次レポート — draft PR #1234 & 手直し + 提出.md"
    let note = try #require(try parse(path))
    #expect(note.title == "週次レポート — draft PR #1234 & 手直し + 提出")
    #expect(note.relativePath == path)
    #expect(note.status == "open")
    #expect(note.projects == ["Sample Project"])
    #expect(note.body.hasPrefix("## 関連"))
}

@Test func datesPriorityAndTheStableIDAreRead() throws {
    let note = try #require(try parse("00_TaskNotes/期限つき.md"))
    #expect(note.due == date(2026, 11, 12))
    #expect(note.dueHasTime == false)
    #expect(note.scheduled == date(2026, 11, 10, 9, 0))
    #expect(note.scheduledHasTime == true)
    #expect(note.priority == "high")
    #expect(note.stableID == "weekly-report")
}

@Test func aTaskWithoutDatesHasNone() throws {
    let note = try #require(try parse("00_TaskNotes/いつか.md"))
    #expect(note.due == nil)
    #expect(note.scheduled == nil)
    #expect(note.stableID == nil)
    #expect(note.projects == [])
}

@Test(arguments: ["00_TaskNotes/メモ.md", "00_TaskNotes/壊れ.md"])
func aFileWithoutAUsableFrontmatterIsNotATask(path: String) throws {
    #expect(try parse(path) == nil)
}

@Test(arguments: [
    ("2026-11-10T09:00:30", 30),
    ("2026-11-10T09:00:30+09:00", 30),
    ("2026-11-10T00:00:00.000Z", 0),
    ("'2026-11-10T09:00'", 0),
])
func timesWithSecondsAndZonesAreAccepted(value: String, seconds: TimeInterval) throws {
    let contents = "---\nstatus: open\nscheduled: \(value)\n---\n"
    let note = try #require(TaskNote.parse(relativePath: "00_TaskNotes/x.md", contents: contents, dialect: .standard, calendar: tokyo))
    #expect(note.scheduled == date(2026, 11, 10, 9, 0).addingTimeInterval(seconds))
    #expect(note.scheduledHasTime == true)
}

@Test func theDialectRenamesTheFieldsItReads() throws {
    var dialect = TaskForgeDialect.standard
    dialect.fields.status = "state"
    let contents = "---\nstate: open\nstatus: done\n---\n"
    let note = try #require(TaskNote.parse(relativePath: "00_TaskNotes/x.md", contents: contents, dialect: dialect, calendar: tokyo))
    #expect(note.status == "open")
}

@Test func theDialectNamesTheFolderAndTheIDField() throws {
    let dialect = TaskForgeDialect.load(vault: fixtureVault)
    #expect(dialect.folder == "00_TaskNotes")
    #expect(dialect.fields.id == "id")
}

@Test func aVaultWithoutADialectFallsBackToTheStandardOne() {
    #expect(TaskForgeDialect.load(vault: URL(filePath: "/nonexistent")) == .standard)
}

@Test(arguments: [
    "---\r\nstatus: open\r\ndue: 2026-11-12\r\n---\r\n本文",
    "\u{FEFF}---\nstatus: open\ndue: 2026-11-12\n---\n本文",
    "---  \nstatus: open\ndue: 2026-11-12\n---  \n本文",
])
func aFrontmatterWithWindowsLineEndingsAByteOrderMarkOrTrailingSpacesIsStillRead(contents: String) throws {
    let note = try #require(TaskNote.parse(relativePath: "a.md", contents: contents, dialect: .standard, calendar: tokyo))
    #expect(note.status == "open")
    #expect(note.due == date(2026, 11, 12))
    #expect(note.body == "本文")
}
