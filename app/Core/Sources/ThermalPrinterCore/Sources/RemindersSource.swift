import EventKit
import Foundation

public protocol RemindersStore: Sendable {
    func requestAccess() async throws -> Bool
    func incompleteReminders(dueBefore end: Date) async -> [ReminderItem]
}

public struct RemindersSource: Sendable {
    public enum Failure: Error, Equatable {
        case accessDenied
    }

    private let store: any RemindersStore
    private let calendar: Calendar

    public init(store: any RemindersStore, calendar: Calendar = .current) {
        self.store = store
        self.calendar = calendar
    }

    public func todaysReminders(now: Date = Date()) async throws -> [ReminderItem] {
        guard try await store.requestAccess() else { throw Failure.accessDenied }
        let end = TodayFilter.endOfToday(now: now, calendar: calendar)
        let fetched = await store.incompleteReminders(dueBefore: end)
        return TodayFilter.reminders(fetched, now: now, calendar: calendar)
    }

    public func todaysCards(now: Date = Date()) async throws -> [Card] {
        try await todaysReminders(now: now).map { ReminderCard.make($0, now: now, calendar: calendar) }
    }
}

public final class EventKitRemindersStore: RemindersStore, @unchecked Sendable {
    private let store = EKEventStore()

    public init() {}

    public func requestAccess() async throws -> Bool {
        try await store.requestFullAccessToReminders()
    }

    public func incompleteReminders(dueBefore end: Date) async -> [ReminderItem] {
        let predicate = store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: end, calendars: nil)
        return await withCheckedContinuation { continuation in
            _ = store.fetchReminders(matching: predicate) { reminders in
                continuation.resume(returning: (reminders ?? []).map(EventKitRemindersStore.item))
            }
        }
    }

    private static func item(_ reminder: EKReminder) -> ReminderItem {
        let components = reminder.dueDateComponents
        let due = components.flatMap { ($0.calendar ?? Calendar.current).date(from: $0) }
        return ReminderItem(
            title: reminder.title ?? "",
            list: reminder.calendar.title,
            due: due,
            dueHasTime: components?.hour != nil,
            notes: reminder.notes
        )
    }
}
