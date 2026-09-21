import XCTest
import SwiftData

/// The synthetic corpus loads, and the Mac's reconcile bridge gives EVERY rated, un-trashed
/// note a row — the rate→row invariant (2026-08-20) run over all ~100 shapes at once.
final class CorpusSeedTests: XCTestCase {

    static var corpusRoot: URL {
        // Skrift_Native/SkriftDesktop/SkriftDesktopTests/<this file> → repo root
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("test-fixtures/corpus", isDirectory: true)
    }

    private func tempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("corpus-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        return dir
    }

    private func cloudContext() throws -> ModelContext {
        ModelContext(try ModelContainer(for: Memo.self, MemoAsset.self, MemoEnhancement.self,
                                        configurations: ModelConfiguration(isStoredInMemoryOnly: true,
                                                                           cloudKitDatabase: .none)))
    }

    private func pipelineContext() throws -> ModelContext {
        ModelContext(try ModelContainer(for: PipelineFile.self,
                                        configurations: ModelConfiguration(isStoredInMemoryOnly: true)))
    }

    func testCorpusSeedsEveryNoteOnce() throws {
        let root = Self.corpusRoot
        try XCTSkipUnless(FileManager.default.fileExists(atPath: root.appendingPathComponent("manifest.json").path),
                          "corpus not generated — run test-fixtures/corpus/generate.py")
        let ctx = try cloudContext()
        let first = try CorpusSeed.seed(from: root, into: ctx, recordingsDirectory: try tempDir())
        let manifest = try JSONDecoder().decode(CorpusSeed.Manifest.self,
                                                from: Data(contentsOf: root.appendingPathComponent("manifest.json")))
        XCTAssertEqual(first.inserted, manifest.count, "every manifest note becomes a Memo")
        XCTAssertGreaterThan(first.assets, manifest.count / 2, "voice notes carry audio, pictures carry photos")
        XCTAssertGreaterThan(first.enhancements, 0)

        let again = try CorpusSeed.seed(from: root, into: ctx, recordingsDirectory: try tempDir())
        XCTAssertEqual(again.inserted, 0, "re-seeding is a no-op")
        XCTAssertEqual(again.skipped, manifest.count)
    }

    func testEveryRatedNoteGetsAMacRowAndNoUnratedOneDoes() throws {
        let root = Self.corpusRoot
        try XCTSkipUnless(FileManager.default.fileExists(atPath: root.appendingPathComponent("manifest.json").path))
        let cloud = try cloudContext()
        try CorpusSeed.seed(from: root, into: cloud, recordingsDirectory: try tempDir())
        let pipeline = try pipelineContext()
        let upload = UploadService(outputDir: try tempDir())

        let memos = try cloud.fetch(FetchDescriptor<Memo>())
        let assets = try cloud.fetch(FetchDescriptor<MemoAsset>())
        var rows = 0, expectedRows = 0
        for memo in memos {
            let mine = assets.filter { $0.memoID == memo.id }
            let row = try MemoCloudIngest.ingest(memo: memo, assets: mine, upload: upload, into: pipeline)
            let shouldHaveRow = memo.deletedAt == nil && NoteConsent.isRated(memo)
            if shouldHaveRow { expectedRows += 1 }
            XCTAssertEqual(row != nil, shouldHaveRow,
                           "\(memo.title ?? memo.id.uuidString): rated=\(NoteConsent.isRated(memo)) trashed=\(memo.deletedAt != nil) row=\(row != nil)")
            if let row { rows += 1; XCTAssertEqual(row.id, memo.id.uuidString, "the row id IS the memo id") }
            // Trust gate on the bridge: a trusted transcript lands verbatim, an untrusted one never.
            if let row, let t = memo.transcript, memo.transcriptStatus == .done, !t.isEmpty {
                let trusted = memo.transcriptUserEdited || (memo.transcriptConfidence ?? 0) >= 0.7
                    || memo.audioFilename.isEmpty
                if trusted { XCTAssertEqual(row.transcript, t) } else { XCTAssertNil(row.transcript) }
            }
        }
        XCTAssertEqual(rows, expectedRows)
        XCTAssertGreaterThan(rows, 60, "most of the corpus is rated")
    }
}
