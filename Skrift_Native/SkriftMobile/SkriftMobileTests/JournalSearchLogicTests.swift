import XCTest
@testable import SkriftMobile

/// Pure result shaping for the search Related section + threads (P8 chunk 6).
final class JournalSearchLogicTests: XCTestCase {

    private func memo(daysAgo: Int, title: String) -> Memo {
        Memo.make(recordedAt: Date().addingTimeInterval(-Double(daysAgo) * 86_400),
                  title: title, transcript: "t", transcriptStatus: .done)
    }

    func testRelatedResultsFloorExclusionOrderAndLimit() {
        let a = memo(daysAgo: 1, title: "a"), b = memo(daysAgo: 2, title: "b")
        let c = memo(daysAgo: 3, title: "c"), d = memo(daysAgo: 4, title: "d")
        let byID = Dictionary(uniqueKeysWithValues: [a, b, c, d].map { ($0.id, $0) })
        let scores: [(memoID: UUID, score: Float)] = [
            (a.id, 0.9),   // exact hit → excluded
            (b.id, 0.5),
            (c.id, 0.7),
            (d.id, 0.1),   // below floor → excluded
        ]
        let out = JournalIndexService.relatedResults(
            scores: scores, excluding: [a.id], memosByID: byID, floor: 0.25, limit: 8)
        XCTAssertEqual(out.map(\.id), [c.id, b.id]) // best-first, a+d gone

        let limited = JournalIndexService.relatedResults(
            scores: scores, excluding: [], memosByID: byID, floor: 0.0, limit: 2)
        XCTAssertEqual(limited.count, 2)
        XCTAssertEqual(limited.first?.id, a.id)
    }

    func testThenVsNowPicksBestOldEnoughPairOrNothing() {
        let cal = Calendar.current
        let now = Date()
        let gapCut = cal.date(byAdding: .month, value: -6, to: now)!
        let newID = UUID(), oldA = UUID(), oldB = UUID(), young = UUID()
        let dates: [UUID: Date] = [
            newID: now,
            oldA: cal.date(byAdding: .month, value: -12, to: now)!,
            oldB: cal.date(byAdding: .month, value: -8, to: now)!,
            young: cal.date(byAdding: .month, value: -2, to: now)!, // too recent for "then"
        ]
        let pair = JournalIndexService.bestThenNow(
            candidates: [(now: newID, hits: [(oldA, 0.6), (oldB, 0.9), (young, 0.95), (oldA, 0.1)])],
            dates: dates, gapCut: gapCut, floor: 0.45)
        XCTAssertEqual(pair, .init(then: oldB, now: newID)) // young excluded, best old wins

        let none = JournalIndexService.bestThenNow(
            candidates: [(now: newID, hits: [(oldA, 0.2)])], // below floor
            dates: dates, gapCut: gapCut, floor: 0.45)
        XCTAssertNil(none)
    }

    func testThreadOrderIncludesSeedOldestFirstAndFloors() {
        let seed = memo(daysAgo: 0, title: "seed")
        let old = memo(daysAgo: 300, title: "old")
        let mid = memo(daysAgo: 100, title: "mid")
        let noise = memo(daysAgo: 50, title: "noise")
        let byID = Dictionary(uniqueKeysWithValues: [seed, old, mid, noise].map { ($0.id, $0) })
        let scores: [(memoID: UUID, score: Float)] = [
            (old.id, 0.8), (mid.id, 0.6), (noise.id, 0.05), // noise below floor
        ]
        let thread = JournalIndexService.threadOrder(
            seedID: seed.id, scores: scores, memosByID: byID, floor: 0.3)
        XCTAssertEqual(thread.map(\.id), [old.id, mid.id, seed.id]) // oldest → seed
        XCTAssertEqual(thread.first?.id, old.id) // first mention
    }
}
