import EventKit
import Foundation
import ThermalPrinterCore

struct TodayReminder: Identifiable, Equatable, Sendable {
    let item: ReminderItem

    var id: String { "reminder:\(item.list)|\(item.title)|\(item.due?.timeIntervalSince1970 ?? 0)" }
}

enum TodayLoader {
    static var remindersAuthorized: Bool {
        EKEventStore.authorizationStatus(for: .reminder) == .fullAccess
    }

    static func reminders(now: Date = Date()) async throws -> [TodayReminder] {
        let source = RemindersSource(store: EventKitRemindersStore())
        return try await source.todaysReminders(now: now).map(TodayReminder.init)
    }

    static func reminderLists() async throws -> [String] {
        try await RemindersSource(store: EventKitRemindersStore()).lists()
    }
}
