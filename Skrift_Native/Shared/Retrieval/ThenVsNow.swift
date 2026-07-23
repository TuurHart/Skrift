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
}
