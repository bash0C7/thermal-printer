import EventKit
import Foundation
import ThermalPrinterCore

struct TodayIssue: Identifiable, Equatable, Sendable {
    let number: Int
    let repository: String
    let title: String
    let url: String

    var id: String { "github:\(url)" }
}

struct TodayReminder: Identifiable, Equatable, Sendable {
    let item: ReminderItem

    var id: String { "reminder:\(item.list)|\(item.title)|\(item.due?.timeIntervalSince1970 ?? 0)" }
}

enum TodayLoadError: Error, LocalizedError {
    case ghMissing
    case ghFailed(String)
    case unreadable

    var errorDescription: String? {
        switch self {
        case .ghMissing: "gh が見つかりません（/opt/homebrew/bin/gh か /usr/local/bin/gh が要ります）"
        case .ghFailed(let line): line.isEmpty ? "gh が失敗しました" : "gh が失敗しました（\(line)）"
        case .unreadable: "gh の応答を読めません"
        }
    }
}

enum TodayLoader {
    static let ghArguments = [
        "search", "issues", "--assignee", "@me", "--state", "open",
        "--sort", "updated", "--limit", "50", "--json", "number,title,repository,url",
    ]

    private struct Row: Decodable {
        struct Repository: Decodable {
            let nameWithOwner: String
        }

        let number: Int
        let title: String
        let url: String
        let repository: Repository
    }

    static func issues(runner: any ProcessRunner, locator: GHLocator = GHLocator()) async throws -> [TodayIssue] {
        guard let gh = locator.locate() else { throw TodayLoadError.ghMissing }
        let outcome = try await runner.run(executable: gh, arguments: ghArguments)
        guard outcome.terminationStatus == 0 else {
            let line = outcome.output.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
            throw TodayLoadError.ghFailed(String(line.prefix(80)))
        }
        guard !outcome.truncated,
              let rows = try? JSONDecoder().decode([Row].self, from: Data(outcome.output.utf8))
        else { throw TodayLoadError.unreadable }
        return rows.map {
            TodayIssue(number: $0.number, repository: $0.repository.nameWithOwner, title: $0.title, url: $0.url)
        }
    }

    static var remindersAuthorized: Bool {
        EKEventStore.authorizationStatus(for: .reminder) == .fullAccess
    }

    static func reminders(now: Date = Date()) async throws -> [TodayReminder] {
        let source = RemindersSource(store: EventKitRemindersStore())
        return try await source.todaysReminders(now: now).map(TodayReminder.init)
    }
}
