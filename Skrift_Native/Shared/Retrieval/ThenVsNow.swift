import Foundation

/// Then vs Now — the Journal's juxtaposition pick: a NEW note (last two weeks)
/// beside its ≥6-month-older semantic kin, the highest-scoring old↔new pair
/// above the related floor. Juxtapose, don't judge: cosine picks the topic, the
/// age gap makes it "then". No qualifying pair → no card.
///
/// MOVED here from the phone's `JournalIndexService` (iPad wave v2, 2026-07-23 —
/// Tuur: "we should have that on all three devices"): one rule, three screens.
/// Each app feeds its own related-scores (phone/iPad `JournalIndexService`,
/// Mac `ConnectionsIndexService`) — the WINDOW + the pick live here.
enum ThenVsNow {
    struct Pair: Equatable, Sendable {
        let then: UUID
        let now: UUID
    }

    /// "New" = recorded within this many days.
    static let recentWindowDays = 14
    /// "Then" = at least this many months older than today.
    static let minGapMonths = 6
    /// How many of the newest notes get a neighbour query per derivation.
    static let maxRecents = 6

    /// The two cut-off dates: notes recorded after `recentCut` are "new", notes recorded on or
    /// before `gapCut` may be "then". nil only if the calendar cannot do the date maths.
    static func window(now: Date, calendar: Calendar = .current) -> (recentCut: Date, gapCut: Date)? {
        guard let recentCut = calendar.date(byAdding: .day, value: -recentWindowDays, to: now),
              let gapCut = calendar.date(byAdding: .month, value: -minGapMonths, to: now) else { return nil }
        return (recentCut, gapCut)
    }

    /// The newest notes that get a neighbour query, and every note's journal date — the two
    /// inputs each app feeds its own related-scores.
    static func recents(in memos: [Memo], since recentCut: Date) -> [Memo] {
        Array(memos.filter { $0.recordedAt >= recentCut }
            .sorted { $0.recordedAt > $1.recordedAt }
            .prefix(maxRecents))
    }

    static func dates(of memos: [Memo]) -> [UUID: Date] {
        Dictionary(memos.map { ($0.id, $0.recordedAt) }, uniquingKeysWith: { a, _ in a })
    }

    /// Pure pair-picking (unit-tested in both suites): best-scoring hit that is
    /// old enough. `candidates` = each recent note's related hits.
    static func pick(candidates: [(now: UUID, hits: [(memoID: UUID, score: Float)])],
                     dates: [UUID: Date], gapCut: Date, floor: Float) -> Pair? {
        var best: (pair: Pair, score: Float)?
        for candidate in candidates {
            for hit in candidate.hits where hit.score >= floor {
                guard let d = dates[hit.memoID], d <= gapCut else { continue }
                if hit.score > (best?.score ?? -1) {
                    best = (Pair(then: hit.memoID, now: candidate.now), hit.score)
                }
            }
        }
        return best?.pair
    }

    /// The whole derivation, once: recents → each one's related-scores → pick. Each app only
    /// supplies `relatedScores` (phone/iPad `JournalIndexService`, Mac `ConnectionsIndexService`)
    /// and the SAME partition of notes: the LIVE one (`MemoLifecycle.partition(...).live`).
    /// SPEC is silent on fading notes here (C231 says only "last ~2 weeks vs >= 6 months
    /// older"), and Review already hides fading notes from every other card, so they are
    /// not offered as a "then" or a "now" either.
    static func derive(memos: [Memo], now: Date = Date(), calendar: Calendar = .current,
                       floor: Float = RetrievalTuning.relatedFloor,
                       relatedScores: (UUID) async -> [(memoID: UUID, score: Float)]) async -> Pair? {
        guard let window = window(now: now, calendar: calendar) else { return nil }
        let dates = dates(of: memos)
        var candidates: [(now: UUID, hits: [(memoID: UUID, score: Float)])] = []
        for memo in recents(in: memos, since: window.recentCut) {
            candidates.append((memo.id, await relatedScores(memo.id)))
        }
        return pick(candidates: candidates, dates: dates, gapCut: window.gapCut, floor: floor)
    }

    // Card copy: one title, one caption, one month count on every device.
    static let cardTitle = "Then vs now"

    /// Whole months between the two notes' journal dates (never below the 6-month rule).
    static func monthsApart(then: Date, now: Date, calendar: Calendar = .current) -> Int {
        calendar.dateComponents([.month], from: then, to: now).month ?? minGapMonths
    }

    static func laterCaption(months: Int) -> String { "\(months) months later" }
}
