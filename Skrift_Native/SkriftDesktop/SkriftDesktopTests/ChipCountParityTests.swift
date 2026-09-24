import XCTest
import SwiftData

/// Q37: the Mac's Needs Work / Unrated chip counts must route through the SAME
/// definitions the iPad's chips use (`WayOutRules`/`ProcessPile`, both Shared), for
/// the SAME corpus — a real device comparison found "Needs Work 6 vs the iPad's 99 ·
/// Unrated 5 vs 6" over one seeded corpus. Root causes, both fixed in
/// `SidebarView.chipCounts`:
///   - Needs Work counted ONLY `files` (PipelineFile rows), so a rated memo waiting
///     on its own row — `WayOutRules.stranded` — was invisible to the chip, while
///     the iPad's `ProcessPile.matches(.needsWork,…)` scans every rated memo with no
///     pipeline-row prerequisite.
///   - Unrated read the band's `unpipelinedMemos`, which excludes a fading note (the
///     right call for the row LIST — the conveyor owns that row) but not for the
///     CHIP, whose doctrine (D135) is "ALL live items". `ProcessPile.unrated` is the
///     one shared definition that doesn't carve fading out.
final class ChipCountParityTests: XCTestCase {

    static var corpusRoot: URL {
        // Skrift_Native/SkriftDesktop/SkriftDesktopTests/<this file> → repo root
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("test-fixtures/corpus", isDirectory: true)
    }

    private func tempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("chipcount-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        return dir
    }

    func testMacAndIPadAgreeOnNeedsWorkAndUnrated() throws {
        let root = Self.corpusRoot
        try XCTSkipUnless(FileManager.default.fileExists(atPath: root.appendingPathComponent("manifest.json").path),
                          "corpus not generated — run test-fixtures/corpus/generate.py")
        let cloud = ModelContext(try ModelContainer(
            for: Memo.self, MemoAsset.self, MemoEnhancement.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)))
        _ = try CorpusSeed.seed(from: root, into: cloud, recordingsDirectory: try tempDir())
        let memos = try cloud.fetch(FetchDescriptor<Memo>())
        XCTAssertGreaterThan(memos.count, 60, "most of the corpus is rated")

        // Mac formula (SidebarView.chipCounts), the freshest possible ingest state:
        // no PipelineFile row exists yet, so every live rated memo is `stranded`.
        let macNeedsWork = WayOutRules.stranded(memos: memos, files: []).count
        let macNotRated = ProcessPile.unrated(memos: memos).count

        // iPad formula (MemosListView.chipCounts) over the SAME memos with nothing
        // processed yet — its `@Query` already excludes trashed memos, mirrored here
        // with the identical predicate before applying the shared match rule.
        let ipadMemos = memos.filter { $0.deletedAt == nil }
        let ipadNeedsWork = ipadMemos.filter { ProcessPile.matches(.needsWork, $0, enhancedIDs: []) }.count
        let ipadNotRated = ProcessPile.unrated(memos: ipadMemos).count

        XCTAssertEqual(macNeedsWork, ipadNeedsWork,
                       "a rated memo with no pipeline row must count toward Needs Work on both devices")
        XCTAssertEqual(macNotRated, ipadNotRated,
                       "Unrated must count the same memos on both devices")
        XCTAssertGreaterThan(macNeedsWork, 0)
        XCTAssertGreaterThan(macNotRated, 0)
    }
}
