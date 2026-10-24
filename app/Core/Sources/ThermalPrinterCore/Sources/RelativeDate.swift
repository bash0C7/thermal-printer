import Foundation

public enum RelativeDate {
    private static let minute = 60
    private static let hour = 60 * minute
    private static let day = 24 * hour
    private static let month = 30 * day
    private static let year = 365 * day

    public static func text(from date: Date, now: Date) -> String {
        let seconds = Int(now.timeIntervalSince(date))
        switch seconds {
        case ..<minute: return "たった今"
        case ..<hour: return "\(seconds / minute)分前"
        case ..<day: return "\(seconds / hour)時間前"
        case ..<month: return "\(seconds / day)日前"
        case ..<year: return "\(seconds / month)か月前"
        default: return "\(seconds / year)年前"
        }
    }
}
