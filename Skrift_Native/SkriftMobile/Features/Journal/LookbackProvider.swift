import Foundation

/// "Looking back" logic for the Journal tab (P8, mock `journal-retrieval.html`).
///
/// Generalizes On This Day for a young corpus: spaced lookbacks at 1/3/6/12
/// months keep the tab alive from month one, and literal "On this day, <year>"
/// cards top the list once prior-year history exists. Pure date math — no ML;
/// ships regardless of the embedding engine.
///
/// Rules (locked in the plan): a window shows its highest-importance memo
/// (ties → newest); empty windows are hidden, never rendered empty; a memo
/// appears in at most one card; today's memos never look back at themselves.
enum LookbackProvider {
    /// ± days around a target date that still counts as "that moment".
    static let windowDays = 3
    static let lookbackMonths = [1, 3, 6, 12]
    /// Young-corpus window (device finding 2026-07-07: a fresh corpus showed
    /// zero cards — the tab must feel alive in week one, not month one).
    static let lookbackWeekDays = 7

    struct Entry: Identifiable, Equatable {
        /// The chosen memo's id (one card per memo).
        let id: UUID
        /// "On this day · 2025" / "1 month ago" / "1 year ago".
        let label: String
        /// The memo's journal date (for the card's date line).
        let date: Date
    }

    /// The memo's date on the journal axis: when it was RECORDED (spoken), not
    /// `createdAt` — that's when it entered Skrift (an import gets today's
    /// `createdAt` but should look back to the moment it captures).
    static func journalDate(_ memo: Memo) -> Date {
        memo.recordedAt
    }

    static func entries(for memos: [Memo], now: Date = Date(),
                        calendar: Calendar = .current) -> [Entry] {
        let eligible = memos.filter { !calendar.isDate(journalDate($0), inSameDayAs: now) }
        var used = Set<UUID>()
        var out: [Entry] = []

        // 1 · literal On This Day — every prior year with a hit, newest year first.
        let years = Set(eligible.map { calendar.component(.year, from: journalDate($0)) })
        let thisYear = calendar.component(.year, from: now)
        for year in years.filter({ $0 < thisYear }).sorted(by: >) {
            var target = calendar.dateComponents([.month, .day], from: now)
            target.year = year
            guard let anchor = calendar.date(from: target) else { continue }
            if let pick = best(in: eligible, around: anchor, calendar: calendar, excluding: used) {
                used.insert(pick.id)
                out.append(Entry(id: pick.id, label: "On this day · \(year)",
                                 date: journalDate(pick)))
            }
        }

        // 2 · spaced lookbacks — a week window first (young corpora), then months.
        if let anchor = calendar.date(byAdding: .day, value: -lookbackWeekDays, to: now),
           let pick = best(in: eligible, around: anchor, calendar: calendar, excluding: used) {
            used.insert(pick.id)
            out.append(Entry(id: pick.id, label: "1 week ago", date: journalDate(pick)))
        }
        for months in lookbackMonths {
            guard let anchor = calendar.date(byAdding: .month, value: -months, to: now)
            else { continue }
            guard let pick = best(in: eligible, around: anchor, calendar: calendar, excluding: used)
            else { continue }
            used.insert(pick.id)
            let label = months == 12 ? "1 year ago"
                : months == 1 ? "1 month ago" : "\(months) months ago"
            out.append(Entry(id: pick.id, label: label, date: journalDate(pick)))
        }
        return out
    }

    /// Highest importance within ±windowDays of `anchor`; ties → newest.
    private static func best(in memos: [Memo], around anchor: Date,
                             calendar: Calendar, excluding used: Set<UUID>) -> Memo? {
        guard let lo = calendar.date(byAdding: .day, value: -windowDays, to: anchor),
              let hi = calendar.date(byAdding: .day, value: windowDays + 1, to: anchor)
        else { return nil }
        return memos
            .filter { !used.contains($0.id) }
            .filter { let d = journalDate($0); return d >= lo && d < hi }
            .max { a, b in
                if a.significance != b.significance { return a.significance < b.significance }
                return journalDate(a) < journalDate(b)
            }
    }

    // ── calendar + map derivations (shared by the Journal screens) ──

    /// Day-of-month → (memo count, any importance-rated) for one displayed month.
    static func dayCounts(for memos: [Memo], month: Date,
                          calendar: Calendar = .current) -> [Int: (count: Int, hot: Bool)] {
        var out: [Int: (count: Int, hot: Bool)] = [:]
        for memo in memos {
            let d = journalDate(memo)
            guard calendar.isDate(d, equalTo: month, toGranularity: .month) else { continue }
            let day = calendar.component(.day, from: d)
            let prev = out[day] ?? (0, false)
            out[day] = (prev.count + 1, prev.hot || memo.significance > 0)
        }
        return out
    }

    static func memos(for memos: [Memo], onDay day: Date,
                      calendar: Calendar = .current) -> [Memo] {
        memos.filter { calendar.isDate(journalDate($0), inSameDayAs: day) }
            .sorted { journalDate($0) < journalDate($1) }
    }
}
