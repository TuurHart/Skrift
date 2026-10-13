import Foundation

/// Relative date labels matching the mockups ("Today · 09:41", "Yesterday · 21:12",
/// "Mon · 14:03"). Moved out of the phone's `MemoDisplay.swift` (Q26, D135/D136 — the
/// unified notes list) so the Mac's queue rows stamp with the SAME clock word and day
/// group as the phone/iPad, instead of the Mac's own lowercase "today" (no time).
enum MemoDate {
    /// C76 / D18: the stored form of "this note has no creation date" (an Apple Notes export
    /// that carries none). `recordedAt` is a non-optional `Date` on both stores, so the unknown
    /// date is ONE sentinel instant (the epoch) that sorts last and never reads as a real day;
    /// every label below turns it into words instead of "1970-01-01".
    static let unknown = Date(timeIntervalSince1970: 0)
    static let unknownLabel = "Date unknown"
    static func isUnknown(_ date: Date) -> Bool { date == unknown }

    /// The date text a detail row shows ("12 Sep 2026"), or "Date unknown".
    static func day(_ date: Date) -> String {
        isUnknown(date) ? unknownLabel : date.formatted(date: .abbreviated, time: .omitted)
    }
    /// The clock time a card kicker shows ("14:29"), or "Date unknown".
    static func time(_ date: Date) -> String {
        isUnknown(date) ? unknownLabel : date.formatted(date: .omitted, time: .shortened)
    }

    static func label(_ date: Date, now: Date = Date()) -> String {
        if isUnknown(date) { return unknownLabel }
        let cal = Calendar.current
        let time = timeFormatter.string(from: date)
        // Day delta against the INJECTED `now` (not `isDateInToday`, which ignores `now` and
        // checks the wall clock — making these labels non-deterministic across midnight).
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: date),
                                      to: cal.startOfDay(for: now)).day ?? 0
        if days <= 0 { return "Today · \(time)" }
        if days == 1 { return "Yesterday · \(time)" }
        // This week → weekday ("Fri · 14:29"). Older than a week, the weekday alone is
        // misleading — a memo from last year read identically to last Friday — so degrade to
        // a real date: same year → "19 Jun · 14:29", a different year → ISO "2025-06-19 · 14:29".
        if days < 7 { return "\(weekdayFormatter.string(from: date)) · \(time)" }
        if cal.component(.year, from: date) == cal.component(.year, from: now) {
            return "\(monthDayFormatter.string(from: date)) · \(time)"
        }
        return "\(isoDateFormatter.string(from: date)) · \(time)"
    }

    /// D190 (Q358) + D197 (Q377): the list's group key, Apple Notes' buckets — "Today", "Yesterday", "Previous 7 Days",
    /// "Previous 30 Days", then the month name this year ("September"), then the year ("2025").
    /// Days count between calendar midnights in `calendar`'s time zone, against the INJECTED
    /// `now` (never the wall clock), so a 25-hour DST day and 23:59 last night both land right.
    /// A future date (clock skew) reads as Today rather than making its own group.
    static func bucket(_ date: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
        if isUnknown(date) { return unknownLabel }
        let days = dayDelta(date, now: now, calendar: calendar)
        if days <= 0 { return "Today" }
        if days == 1 { return "Yesterday" }
        if days <= 7 { return "Previous 7 Days" }
        if days <= 30 { return "Previous 30 Days" }
        let year = calendar.component(.year, from: date)
        guard year == calendar.component(.year, from: now) else { return String(year) }
        return calendar.standaloneMonthSymbols[calendar.component(.month, from: date) - 1]
    }

    /// D190 (Q358): the date that leads a row's line 2 — "09:41" today, "Yesterday", the
    /// weekday within the week ("Friday"), "27 Sep" this year, "24/12/2025" before. The detail
    /// the old per-day headers carried now lives here.
    static func listDate(_ date: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
        if isUnknown(date) { return unknownLabel }
        let days = dayDelta(date, now: now, calendar: calendar)
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute, .weekday], from: date)
        if days <= 0 { return String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0) }
        if days == 1 { return "Yesterday" }
        if days <= 7 { return calendar.standaloneWeekdaySymbols[(c.weekday ?? 1) - 1] }
        if c.year == calendar.component(.year, from: now) {
            return "\(c.day ?? 1) \(calendar.shortStandaloneMonthSymbols[(c.month ?? 1) - 1])"
        }
        return "\(c.day ?? 1)/\(c.month ?? 1)/\(c.year ?? 0)"
    }

    /// Whole calendar days from `date`'s midnight to `now`'s midnight (negative = future).
    private static func dayDelta(_ date: Date, now: Date, calendar: Calendar) -> Int {
        calendar.dateComponents([.day], from: calendar.startOfDay(for: date),
                                to: calendar.startOfDay(for: now)).day ?? 0
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "HH:mm"; return f
    }()
    private static let weekdayFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "EEE"; return f
    }()
    private static let monthDayFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "d MMM"; return f
    }()
    private static let isoDateFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f
    }()
}
