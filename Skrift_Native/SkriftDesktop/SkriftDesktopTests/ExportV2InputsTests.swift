import XCTest
import SwiftData

/// Q511 (C25, C64, D12, C2): export v2's swap prerequisites. A synced memo's `createdAt` and
/// whether he typed its title reach `ExportV2.Note` on the Mac through the row (mirrored
/// pull-only, like `editedAt`), exactly as the Q434 harness used to read them off the memo; a
/// phone edit moves them; reconcile v2's field table carries both; the swap switch is off.
@MainActor
final class ExportV2InputsTests: XCTestCase {
    typealias H = ExportDiffHarnessTests

    private func scratch() -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("Q511-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        return dir
    }

    /// Every corpus note's row builds the v2 note the harness built from the memo.
    func testEveryCorpusRowCarriesTheMemosCreatedAtAndTitleOrigin() throws {
        let root = H.corpusRoot
        try XCTSkipUnless(FileManager.default.fileExists(atPath: root.appendingPathComponent("manifest.json").path))
        let work = scratch()
        let cloud = ModelContext(try ModelContainer(
            for: Memo.self, MemoAsset.self, MemoEnhancement.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)))
        let pipeline = ModelContext(try ModelContainer(
            for: PipelineFile.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true)))
        try CorpusSeed.seed(from: root, into: cloud, recordingsDirectory: work.appendingPathComponent("phone"))
        V2.sweep(cloud, into: pipeline, outputDir: work.appendingPathComponent("mac"))
        let rows = Dictionary(try pipeline.fetch(FetchDescriptor<PipelineFile>()).map { ($0.id, $0) },
                              uniquingKeysWith: { a, _ in a })
        var checked = 0, his = 0
        for memo in try cloud.fetch(FetchDescriptor<Memo>()) {
            guard let pf = rows[memo.id.uuidString] else { continue }
            let note = VaultExporter.v2Note(pf, people: [], author: "Tiuri")
            let gave = !(memo.title ?? "").trimmingCharacters(in: .whitespaces).isEmpty
            XCTAssertEqual(note.createdAt, memo.createdAt, "\(memo.id): created")
            XCTAssertEqual(note.heGaveTitle, gave, "\(memo.id): title origin")
            checked += 1
            if gave { his += 1 }
        }
        XCTAssertGreaterThanOrEqual(checked, 80, "the corpus's ingested notes")
        XCTAssertGreaterThan(his, 0, "some carry a title he typed")
        XCTAssertLessThan(his, checked, "and some do not")
    }

    func testAPhoneEditMovesBothOntoTheRow() {
        let memo = Memo(title: nil, transcript: "Kiln notes.")
        memo.createdAt = Date(timeIntervalSince1970: 1_790_000_000)
        let pf = PipelineFile(id: memo.id.uuidString, filename: "memo.m4a")
        let v1 = Dictionary(ReconcileV2.Fields.all.map { ($0.name, $0) }, uniquingKeysWith: { a, _ in a })
        XCTAssertTrue(v1["createdAt"]!.pull(memo, pf))
        XCTAssertEqual(pf.memoCreatedAt, memo.createdAt)
        XCTAssertFalse(v1["titleIsHis"]!.pull(memo, pf), "no title of his: nothing to change")
        memo.title = "Kiln wiring"
        XCTAssertTrue(v1["titleIsHis"]!.pull(memo, pf))
        XCTAssertTrue(pf.memoTitleIsHis)
        XCTAssertTrue(v1["titleIsHis"]!.recompiles, "in the frontmatter (C130)")
        XCTAssertTrue(v1["createdAt"]!.recompiles)
        memo.title = "  "
        XCTAssertTrue(v1["titleIsHis"]!.pull(memo, pf))
        XCTAssertFalse(pf.memoTitleIsHis, "a blank title is no title")
    }

    func testReconcileV2CarriesTheSameTwoFields() {
        let memo = Memo(title: "Kiln wiring", transcript: "Kiln notes.")
        memo.createdAt = Date(timeIntervalSince1970: 1_790_000_000)
        let pf = PipelineFile(id: memo.id.uuidString, filename: "memo.m4a")
        let v2 = Dictionary(ReconcileV2.Fields.all.map { ($0.name, $0) }, uniquingKeysWith: { a, _ in a })
        XCTAssertTrue(v2["createdAt"]?.pull(memo, pf) ?? false)
        XCTAssertTrue(v2["titleIsHis"]?.pull(memo, pf) ?? false)
        XCTAssertEqual(pf.memoCreatedAt, memo.createdAt)
        XCTAssertTrue(pf.memoTitleIsHis)
    }

    func testTheMacNoteFeedsCreatedAndThePortfolioTitle() {
        let pf = PipelineFile(id: UUID().uuidString, filename: "memo.m4a")
        pf.transcript = "Words about the kiln."
        pf.memoCreatedAt = Date(timeIntervalSince1970: 1_790_000_000)
        pf.memoTitleIsHis = true
        pf.enhancedTitle = "Kiln wiring"
        let note = VaultExporter.v2Note(pf, people: [], author: "Tiuri")
        let vault = ExportV2.compile(note, profile: .obsidian, stem: "s").markdown
        XCTAssertTrue(vault.contains("\ncreated: " + ExportNaming.localDateTime(pf.memoCreatedAt!) + "\n"), vault)
        XCTAssertTrue(ExportV2.compile(note, profile: .portfolio, stem: "s").markdown.contains("title: \"Kiln wiring\""))
    }
}
