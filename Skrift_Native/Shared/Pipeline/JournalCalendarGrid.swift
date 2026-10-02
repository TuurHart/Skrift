import Foundation

/// The Journal's month grid, built once for phone Calendar, the iPad pane and the Mac rail
/// (recsj-091/-092): the day cells, the weekday header, the dot rule and the first-day rule.
/// Each app only draws it.
enum JournalCalendarGrid {
    /// One displayed month, padded with leading/trailing nils to full weeks (nil = blank cell).
    static func days(in month: Date, calendar: Calendar = .current) -> [Date?] {
        guard let interval = calendar.dateInterval(of: .month, for: month),
              let dayCount = calendar.range(of: .day, in: .month, for: month)?.count
        else { return [] }
        let weekday = calendar.component(.weekday, from: interval.start)
        let lead = (weekday - calendar.firstWeekday + 7) % 7
        var out: [Date?] = Array(repeating: nil, count: lead)
        for d in 0..<dayCount {
            out.append(calendar.date(byAdding: .day, value: d, to: interval.start))
        }
        while out.count % 7 != 0 { out.append(nil) }
        return out
    }

    /// The header row, starting on the calendar's first weekday.
    static func weekdaySymbols(calendar: Calendar = .current) -> [String] {
        let symbols = calendar.veryShortWeekdaySymbols
        let shift = calendar.firstWeekday - 1
        return Array(symbols[shift...] + symbols[..<shift])
    }

    /// The dot rule (phone look): one dot per note up to three; full strength when any note
    /// of the day is rated, dim otherwise.
    static func dots(count: Int, hot: Bool) -> (count: Int, strong: Bool) {
        (max(0, min(count, 3)), hot)
    }
    static let dimDotOpacity = 0.45

    /// The first-day rule: every calendar opens with TODAY selected.
    static func firstSelectedDay(now: Date = Date(), calendar: Calendar = .current) -> Date {
        calendar.startOfDay(for: now)
    }
}
