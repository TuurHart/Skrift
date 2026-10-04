import XCTest
@testable import SkriftMobile

/// Q283 (D168): the phone's chip row no longer offers Unsynced, and `MemoFilter` no longer
/// carries the dead Unsynced / Photos / Place terms. Nothing sets `syncStatus = .synced`
/// outside seeders under CloudKit, so the chip could only ever show everything.
@MainActor
final class FilterChipsPrunedTests: XCTestCase {

    private func memo(_ status: SyncStatus) -> Memo {
        let m = Memo(audioFilename: "x.m4a", transcript: "some words", transcriptStatus: .done,
                     significance: 0.5)
        m.syncStatus = status
        return m
    }

    /// The status chips are the shared `QueueFilter`; none of them is Unsynced.
    func testStatusChipsOfferNoUnsynced() {
        for c in QueueFilter.allCases {
            XCTAssertFalse(c.rawValue.lowercased().contains("unsynced"), c.rawValue)
        }
    }

    /// The filter value holds the date range only: no unsyncedOnly / hasPhotosOnly / place.
    func testMemoFilterCarriesOnlyTheDateRange() {
        let labels = Set(Mirror(reflecting: MemoFilter()).children.compactMap(\.label))
        XCTAssertEqual(labels, ["dateField", "from", "to"])
        XCTAssertFalse(MemoFilter().isActive)
        XCTAssertTrue(MemoFilter(from: Date()).isActive)
    }

    /// Synced and unsynced memos pass the list filter identically (no hidden sync-status term).
    func testSyncStatusNoLongerFiltersTheList() {
        let a = memo(.synced), b = memo(.waiting)
        for c in QueueFilter.allCases {
            XCTAssertEqual(MemosListView.passesFilter(a, chip: c, filter: MemoFilter(), enhanced: []),
                           MemosListView.passesFilter(b, chip: c, filter: MemoFilter(), enhanced: []), "\(c)")
        }
    }

    /// The chip row's own source declares no Unsynced chip and no `chip-unsynced` test id.
    func testChipRowSourceHasNoUnsyncedChip() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // SkriftMobileTests
            .deletingLastPathComponent()   // SkriftMobile
            .appendingPathComponent("Features/MemosList/MemosListView+Header.swift")
        let code = try String(contentsOf: url, encoding: .utf8)
            .split(separator: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
        XCTAssertFalse(code.contains("\"Unsynced\""))
        XCTAssertFalse(code.contains("chip-unsynced"))
    }
}
