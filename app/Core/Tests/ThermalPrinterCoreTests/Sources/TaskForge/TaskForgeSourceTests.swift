import Foundation
import Testing
@testable import ThermalPrinterCore

private func note(
    _ title: String, status: String = "open", priority: String? = nil, due: Date? = nil, scheduled: Date? = nil
) -> TaskNote {
    TaskNote(title: title, relativePath: "00_TaskNotes/\(title).md", status: status, priority: priority,
             due: due, dueHasTime: false, scheduled: scheduled, scheduledHasTime: false,
             projects: [], stableID: nil, body: "")
}

private let earlierDay = Date(timeIntervalSince1970: 1_794_000_000)
private let laterDay = earlierDay.addingTimeInterval(86_400)

@Test func doneAndCancelledTasksAndNonTasksAreLeftOut() throws {
    let titles = try TaskForgeSource.openTasks(vault: fixtureVault).map(\.title)
    #expect(Set(titles) == ["週次レポート — draft PR #1234 & 手直し + 提出", "期限つき", "いつか"])
}

@Test(arguments: ["done", "cancelled"])
func finishedStatusesAreNotOpen(status: String) {
    #expect(TaskForgeSource.isOpen(note("t", status: status)) == false)
}

@Test(arguments: ["open", "planned", "someday", "deferred", "in-progress", "on-hold", "blocked", "ready"])
func everyOtherStatusIsListedBecauseItIsNotFinished(status: String) {
    #expect(TaskForgeSource.isOpen(note("t", status: status)))
}

@Test func statusesFollowTaskForgesDefinitionOrderAndUnknownOnesComeLast() {
    let statuses = ["weird", "ready", "someday", "blocked", "deferred", "planned", "on-hold", "in-progress", "open"]
    let notes = statuses.map { note($0, status: $0) }
    #expect(TaskForgeSource.sorted(notes).map(\.status)
        == ["open", "in-progress", "on-hold", "planned", "deferred", "blocked", "someday", "ready", "weird"])
}

@Test func theStatusOutranksEveryDate() {
    let someday = note("someday", status: "someday", due: earlierDay, scheduled: earlierDay)
    let open = note("open", status: "open")
    #expect(TaskForgeSource.sorted([someday, open]).map(\.title) == ["open", "someday"])
}

@Test func withinAStatusAnEarlierDueDateComesFirstAndTasksWithoutOneComeLast() {
    let none = note("none")
    let later = note("later", due: laterDay)
    let sooner = note("sooner", due: earlierDay)
    #expect(TaskForgeSource.sorted([none, later, sooner]).map(\.title) == ["sooner", "later", "none"])
}

@Test func theScheduledDateBreaksTiesBetweenEqualDueDates() {
    let noStart = note("noStart", due: earlierDay)
    let lateStart = note("lateStart", due: earlierDay, scheduled: laterDay)
    let earlyStart = note("earlyStart", due: earlierDay, scheduled: earlierDay)
    #expect(TaskForgeSource.sorted([noStart, lateStart, earlyStart]).map(\.title)
        == ["earlyStart", "lateStart", "noStart"])
}

@Test func thePriorityNoLongerDecidesTheOrder() {
    #expect(TaskForgeSource.sorted([note("b", priority: "highest"), note("a", priority: "lowest")]).map(\.title)
        == ["a", "b"])
}

@Test func equalTasksFallBackToTheTitle() {
    #expect(TaskForgeSource.sorted([note("b"), note("a")]).map(\.title) == ["a", "b"])
}

@Test func theTaskIDIsItsPathInTheVault() {
    #expect(note("a").id == "task:00_TaskNotes/a.md")
}

@Test func aMissingVaultIsReportedByItsPath() {
    #expect(throws: TaskForgeSourceError.vaultMissing("/nonexistent")) {
        try TaskForgeSource.openTasks(vault: URL(filePath: "/nonexistent"))
    }
}

@Test func theMissingVaultMessageNamesThePath() {
    #expect(TaskForgeSourceError.vaultMissing("/nonexistent").errorDescription == "vault が見つかりません（/nonexistent）")
}

@Test func aTypedVaultPathLosesSurroundingWhitespaceAndExpandsTheHome() {
    #expect(TaskForgeSource.vaultPath(from: "  ~/notes/my-vault \n") == NSHomeDirectory() + "/notes/my-vault")
    #expect(TaskForgeSource.vaultPath(from: "/tmp/my-vault") == "/tmp/my-vault")
    #expect(TaskForgeSource.vaultPath(from: " \n") == "")
}
