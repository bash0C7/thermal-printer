import Foundation

public struct ReminderItem: Equatable, Sendable {
    public var title: String
    public var list: String
    public var due: Date?
    public var dueHasTime: Bool
    public var notes: String?

    public init(title: String, list: String, due: Date?, dueHasTime: Bool = true, notes: String?) {
        self.title = title
        self.list = list
        self.due = due
        self.dueHasTime = dueHasTime
        self.notes = notes
    }
}

public enum TodayFilter {
    public static func reminders(_ items: [ReminderItem], now: Date, calendar: Calendar = .current) -> [ReminderItem] {
        let start = calendar.startOfDay(for: now)
        return items
            .filter { $0.due.map { $0 >= start } ?? false }
            .sorted { ($0.due ?? .distantFuture) < ($1.due ?? .distantFuture) }
    }
}

public enum ReminderCard {
    private static let weekdays = ["日", "月", "火", "水", "木", "金", "土"]

    public static func make(_ item: ReminderItem, now: Date, calendar: Calendar = .current) -> Card {
        let notes = item.notes?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return Card(
            kind: .reminder, url: nil,
            header: Card.Header(lines: [item.list], sublines: dueLine(item, now: now, calendar: calendar).map { [$0] } ?? []),
            title: "☐ " + item.title,
            sections: notes.isEmpty ? [] : [Card.Section(text: notes)]
        )
    }

    private static func dueLine(_ item: ReminderItem, now: Date, calendar: Calendar) -> String? {
        guard let due = item.due else { return nil }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: due)).day ?? 0
        var text = "期限 " + dayText(due, days: days, now: now, calendar: calendar)
        if item.dueHasTime {
            let time = calendar.dateComponents([.hour, .minute], from: due)
            text += String(format: " %02d:%02d", time.hour ?? 0, time.minute ?? 0)
        }
        return text
    }

    private static func dayText(_ due: Date, days: Int, now: Date, calendar: Calendar) -> String {
        switch days {
        case 0: return "今日"
        case -1: return "昨日"
        case 1: return "明日"
        default:
            let parts = calendar.dateComponents([.year, .month, .day, .weekday], from: due)
            let weekday = weekdays[((parts.weekday ?? 1) - 1) % 7]
            let monthDay = "\(parts.month ?? 0)/\(parts.day ?? 0)(\(weekday))"
            return parts.year == calendar.component(.year, from: now) ? monthDay : "\(parts.year ?? 0)/" + monthDay
        }
    }
}
