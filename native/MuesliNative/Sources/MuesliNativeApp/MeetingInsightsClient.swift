import Foundation
import MuesliCore

/// How far back the Insights chat (task 1) reads when it assembles context
/// from the user's meetings. Replaces the old `InsightsPeriod` — a chat can
/// jump between "everything" and one specific day, not just three fixed windows.
enum InsightsDateRange: Equatable, Hashable, Sendable {
    case allTime
    case today
    case week
    case month
    case specificDay(Date)

    static let `default`: InsightsDateRange = .week

    var title: String {
        switch self {
        case .allTime: return tr("All time", "Всё время")
        case .today: return tr("Today", "Сегодня")
        case .week: return tr("Week", "Неделя")
        case .month: return tr("Month", "Месяц")
        case .specificDay(let date):
            let formatter = DateFormatter()
            formatter.setLocalizedDateFormatFromTemplate("d MMM")
            return formatter.string(from: date)
        }
    }

    /// The half-open interval `[start, end)` a meeting's start time must fall
    /// into. `nil` means no filtering (all time).
    func interval(now: Date = Date(), calendar: Calendar = .current) -> (start: Date, end: Date)? {
        switch self {
        case .allTime:
            return nil
        case .today:
            let start = calendar.startOfDay(for: now)
            let end = calendar.date(byAdding: .day, value: 1, to: start) ?? now.addingTimeInterval(1)
            return (start, end)
        case .week:
            let start = calendar.date(byAdding: .day, value: -7, to: now) ?? now
            return (start, now.addingTimeInterval(1))
        case .month:
            let start = calendar.date(byAdding: .day, value: -31, to: now) ?? now
            return (start, now.addingTimeInterval(1))
        case .specificDay(let date):
            let start = calendar.startOfDay(for: date)
            let end = calendar.date(byAdding: .day, value: 1, to: start) ?? date.addingTimeInterval(86400)
            return (start, end)
        }
    }
}

/// Compact per-meeting input for the Insights chat's context.
struct MeetingDigestInput: Sendable {
    let date: String
    let title: String
    let summary: String
}
