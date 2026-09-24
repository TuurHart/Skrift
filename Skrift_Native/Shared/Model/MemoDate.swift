import Foundation

/// Relative date labels matching the mockups ("Today · 09:41", "Yesterday · 21:12",
/// "Mon · 14:03"). Moved out of the phone's `MemoDisplay.swift` (Q26, D135/D136 — the
/// unified notes list) so the Mac's queue rows stamp with the SAME clock word and day
/// group as the phone/iPad, instead of the Mac's own lowercase "today" (no time).
enum MemoDate {
    static func label(_ date: Date, now: Date = Date()) -> String {
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

    /// Day-group header key for the list ("Today" / "Yesterday" / "Mon 3 Jun").
    static func group(_ date: Date, now: Date = Date()) -> String {
        let cal = Calendar.current
        // Day delta against the injected `now` (deterministic across midnight — see `label`).
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: date),
                                      to: cal.startOfDay(for: now)).day ?? 0
        if days <= 0 { return "Today" }
        if days == 1 { return "Yesterday" }
        // Carry the year on a different-year group so old day-groups aren't ambiguous.
        if cal.component(.year, from: date) == cal.component(.year, from: now) {
            return groupFormatter.string(from: date)
        }
        return groupYearFormatter.string(from: date)
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "HH:mm"; return f
    }()
    private static let weekdayFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "EEE"; return f
    }()
    private static let groupFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "EEE d MMM"; return f
    }()
    private static let monthDayFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "d MMM"; return f
    }()
    private static let isoDateFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f
    }()
    private static let groupYearFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "EEE d MMM yyyy"; return f
    }()
}
