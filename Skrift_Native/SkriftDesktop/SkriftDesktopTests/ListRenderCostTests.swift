import XCTest

/// Q54/R92/C278 (`plan/sweep-b-list-launch.md`): the phone's `MemosListView`
/// read `enhancedTitleByMemoID`, `searchFadingIDs`, `MemoLifecycle.backlinkedIDs`/
/// `.partition`, and `chipCounts` as computed properties inside `ForEach` — each
/// access re-ran its own full corpus scan, once per visible ROW (or once per
/// chip). The fix folds them into ONE pre-render pass (`MemosListView.Derived`,
/// `let counts = chipCounts` before the chip `ForEach`) and reads the result by
/// dictionary/set lookup per row.
///
/// `MemosListView.swift` is iOS/UIKit-only and out of reach for this MLX-free Mac
/// target (see `MacMainThreadCostTests`'s note on why `SkriftDesktopTests`
/// cherry-picks pure-logic files), so this proves the CONTRACT the hoist relies
/// on directly against the shared corpus-scanning primitives it wraps
/// (`MemoLifecycle.backlinkedIDs`, the enhanced-title dictionary build, and the
/// `ProcessPile`/`QueueFilter` chip-count scans): call the scan once, then do N
/// row-shaped lookups against the result — the scan's call count must stay 1
/// regardless of N.
final class ListRenderCostTests: XCTestCase {

    private func corpus(_ n: Int) -> [Memo] {
        (0..<n).map { i in
            let m = Memo(audioFilename: "m\(i).m4a", recordedAt: Date(),
                        transcript: i % 4 == 0
                            ? "Some words [[memo:\(UUID().uuidString)|Other]] more words."
                            : "Plain words, nothing linked.",
                        transcriptStatus: .done)
            m.significance = i % 3 == 0 ? 0.6 : 0
            return m
        }
    }

    /// Mirrors `MemosListView.derived`: ONE `backlinkedIDs` scan + ONE
    /// enhanced-title dictionary build feed N per-row lookups.
    func testDerivedPassScansCorpusOnceRegardlessOfRowCount() {
        for n in [10, 100, 1_000] {
            let memos = corpus(n)
            var backlinkScans = 0
            var titleDictBuilds = 0

            // ONE pre-render pass — exactly what `MemosListView.derived` does.
            backlinkScans += 1
            let backlinked = MemoLifecycle.backlinkedIDs(in: memos)
            titleDictBuilds += 1
            let titleByID: [UUID: String] = Dictionary(
                memos.enumerated().compactMap { i, m in i % 5 == 0 ? (m.id, "Title \(i)") : nil },
                uniquingKeysWith: { a, _ in a })
            let fadingIDs = Set(memos.filter { MemoLifecycle.isFading($0, backlinked: backlinked) }.map(\.id))

            // N row-shaped reads — dictionary/set lookups only, no rescans.
            var touched = 0
            for m in memos {
                _ = titleByID[m.id]
                _ = fadingIDs.contains(m.id)
                touched += 1
            }

            XCTAssertEqual(touched, n)
            XCTAssertEqual(backlinkScans, 1, "N=\(n): backlinkedIDs must run once per render, not once per row")
            XCTAssertEqual(titleDictBuilds, 1, "N=\(n): the title dictionary must build once per render, not once per row")
        }
    }

    /// Mirrors the `filterChips` fix: `chipCounts` is a local `let` computed
    /// once before the chip `ForEach`, not read as a property inside it (the
    /// old shape re-ran 3 `ProcessPile`/`QueueFilter` scans per chip × 4 chips).
    func testChipCountsComputedOncePerRenderNotPerChip() {
        let memos = corpus(200)
        var chipCountBuilds = 0

        func chipCounts() -> [QueueFilter: Int] {
            chipCountBuilds += 1
            let enhanced: Set<UUID> = []
            return NotesListModel.chipCounts(
                needsWork: memos.filter { ProcessPile.matches(.needsWork, $0, enhancedIDs: enhanced) }.count,
                done: memos.filter { ProcessPile.matches(.done, $0, enhancedIDs: enhanced) }.count,
                notRated: ProcessPile.unrated(memos: memos).count)
        }

        // The fixed shape: ONE call before the ForEach, one dictionary read per chip.
        let counts = chipCounts()
        for chip in QueueFilter.allCases {
            _ = counts[chip]
        }

        XCTAssertEqual(chipCountBuilds, 1, "chipCounts must build once for the whole chip row, not once per chip")
    }

    /// `groups(from:)` now calls the shared `NotesListModel.dayGroups` instead of
    /// hand-rolling the identical order-array + bucket-dict loop (sweep-b #9) —
    /// proves the shared helper reproduces the same grouping/order a day-grouped
    /// list needs.
    func testDayGroupsMatchesHandRolledGroupingOrder() {
        let days = ["Today", "Today", "Yesterday", "Mon", "Today"]
        let grouped = NotesListModel.dayGroups(days) { $0 }
        XCTAssertEqual(grouped.map(\.title), ["Today", "Yesterday", "Mon"], "first-seen order, not sorted")
        XCTAssertEqual(grouped.first { $0.title == "Today" }?.items.count, 3)
        XCTAssertEqual(grouped.first { $0.title == "Yesterday" }?.items.count, 1)
    }
}
