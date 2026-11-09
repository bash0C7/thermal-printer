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

@Test func tasksAreOrderedByScheduledThenDueThenPriority() {
    let a = note("a", scheduled: earlierDay)
    let b = note("b", due: laterDay)
    let c = note("c", priority: "high")
    let d = note("d", priority: "low")
    #expect(TaskForgeSource.sorted([d, c, b, a]).map(\.title) == ["a", "b", "c", "d"])
}

@Test func anEarlierScheduledDateComesFirstAndADueDateBreaksTies() {
    let late = note("late", scheduled: laterDay)
    let earlyDueLater = note("earlyDueLater", due: laterDay, scheduled: earlierDay)
    let earlyDueSooner = note("earlyDueSooner", due: earlierDay, scheduled: earlierDay)
    #expect(TaskForgeSource.sorted([late, earlyDueLater, earlyDueSooner]).map(\.title)
        == ["earlyDueSooner", "earlyDueLater", "late"])
}

@Test func priorityRunsFromHighestDownAndUnknownCountsAsNone() {
    let titles = ["lowest", "none", "highest", "medium", "weird", "low", "high"]
    let notes = titles.map { note($0, priority: $0) }
    #expect(TaskForgeSource.sorted(notes).map(\.title) == ["highest", "high", "medium", "low", "lowest", "none", "weird"])
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
