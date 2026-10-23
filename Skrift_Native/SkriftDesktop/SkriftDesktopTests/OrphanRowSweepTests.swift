import XCTest
import SwiftData
import Foundation

/// C157 / Q487: a Mac row whose memo is gone (purged on another device) is trashed on the next
/// sweep — never its vault file — and is never authored back. Synthetic in-memory stores only.
@MainActor
final class OrphanRowSweepTests: XCTestCase {

    private var scratch: URL!
    private lazy var upload = UploadService(outputDir: scratch.appendingPathComponent("out", isDirectory: true))

    override func setUpWithError() throws {
        scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("q487_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: scratch)
        super.tearDown()
    }

    private func stores() throws -> (cloud: ModelContext, local: ModelContext) {
        let cloud = try ModelContainer(for: Memo.self, MemoAsset.self, MemoEnhancement.self, MemoEditHead.self,
                                       configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let local = try ModelContainer(for: PipelineFile.self,
                                       configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        return (ModelContext(cloud), ModelContext(local))
    }

    @discardableResult
    private func seedMemo(_ cloud: ModelContext, id: UUID = UUID()) -> Memo {
        let memo = Memo(id: id, audioFilename: "memo_\(id.uuidString).m4a", recordedAt: Date(),
                        transcript: "Words of \(id.uuidString.prefix(4)).", transcriptStatus: .done,
                        transcriptConfidence: 0.9, significance: 0.6)
        cloud.insert(memo)
        cloud.insert(MemoAsset(memoID: id, kind: MemoAsset.Kind.audio,
                               filename: MemoCloudIngest.audioFilename(for: memo), blob: Data("AUDIO".utf8)))
        return memo
    }

    private func pass(_ s: (cloud: ModelContext, local: ModelContext), firstImportDone: Bool = true,
                      now: Date = Date()) throws -> MemoCloudReconciler.PassOutcome {
        try MemoCloudReconciler.pass(from: s.cloud, into: s.local, thisDeviceID: "mac-test", now: now,
                                     upload: upload, firstImportDone: firstImportDone)
    }

    private func rows(_ s: (cloud: ModelContext, local: ModelContext)) throws -> [String: PipelineFile] {
        Dictionary(uniqueKeysWithValues: try s.local.fetch(FetchDescriptor<PipelineFile>()).map { ($0.id, $0) })
    }

    /// Ingest `n` memos, then purge the first `purged` of them from the cloud store.
    private func ingestThenPurge(_ s: (cloud: ModelContext, local: ModelContext), n: Int, purged: Int) throws -> [UUID] {
        let ids = (0..<n).map { _ in UUID() }
        for id in ids { seedMemo(s.cloud, id: id) }
        try s.cloud.save()
        try pass(s)
        XCTAssertEqual(try rows(s).count, n, "every memo got its row")
        for id in ids.prefix(purged) {
            for m in try s.cloud.fetch(FetchDescriptor<Memo>(predicate: #Predicate { $0.id == id })) { s.cloud.delete(m) }
        }
        try s.cloud.save()
        return ids
    }

    func testARowWhoseMemoWasPurgedIsTrashedOnTheNextSweep() throws {
        let s = try stores()
        let ids = try ingestThenPurge(s, n: 8, purged: 1)
        let now = Date().addingTimeInterval(60)

        let outcome = try pass(s, now: now)

        XCTAssertEqual(outcome.orphansTrashed, 1)
        let byID = try rows(s)
        XCTAssertEqual(byID[ids[0].uuidString]?.deletedAt, now, "the orphan goes to the trash, not away")
        for id in ids.dropFirst() { XCTAssertNil(byID[id.uuidString]?.deletedAt, "a row with its memo stays") }
        XCTAssertEqual(try pass(s).orphansTrashed, 0, "a trashed orphan is not trashed again")
    }

    func testAMacCaptureWhoseMemoWasPurgedIsNeverAuthoredBack() throws {
        let s = try stores()
        try ingestThenPurge(s, n: 8, purged: 0)
        // A Mac import the backfill authors a memo for, which the phone later purges.
        let audio = scratch.appendingPathComponent("dropped.m4a")
        try Data("AUDIO".utf8).write(to: audio)
        let pf = PipelineFile(id: UUID().uuidString, filename: "dropped.m4a", path: audio.path, sourceType: .audio)
        pf.isLocalImport = true
        s.local.insert(pf)
        try s.local.save()
        XCTAssertEqual(try pass(s).authored, 1)
        try pass(s)
        XCTAssertNotNil(pf.syncedSourceEditedAt, "the next sweep sees its memo and baselines the row")
        let id = try XCTUnwrap(UUID(uuidString: pf.id))
        for m in try s.cloud.fetch(FetchDescriptor<Memo>(predicate: #Predicate { $0.id == id })) { s.cloud.delete(m) }
        try s.cloud.save()

        let outcome = try pass(s)

        XCTAssertEqual(outcome.orphansTrashed, 1)
        XCTAssertEqual(outcome.authored, 0, "a purged note never comes back from the Mac")
        XCTAssertNotNil(try rows(s)[pf.id]?.deletedAt)
        XCTAssertEqual(try s.cloud.fetchCount(FetchDescriptor<Memo>(predicate: #Predicate { $0.id == id })), 0)
    }

    func testAnUnauthoredMacCaptureIsNotAnOrphan() throws {
        let s = try stores()
        try ingestThenPurge(s, n: 8, purged: 0)
        let pf = PipelineFile(id: UUID().uuidString, filename: "fresh.m4a", path: "", sourceType: .audio)
        pf.isLocalImport = true
        s.local.insert(pf)
        try s.local.save()

        XCTAssertEqual(try pass(s).orphansTrashed, 0, "it never had a memo, so none is missing")
        XCTAssertNil(try rows(s)[pf.id]?.deletedAt)
    }

    func testNothingIsTrashedBeforeTheFirstImportIsDone() throws {
        let s = try stores()
        try ingestThenPurge(s, n: 8, purged: 1)
        XCTAssertEqual(try pass(s, firstImportDone: false).orphansTrashed, 0,
                       "a memo that has not downloaded yet is not gone")
    }

    func testADifferentOrEmptyStoreTrashesNothing() throws {
        // Most of the memos missing at once is a store switch or a half download, not purges.
        let s = try stores()
        try ingestThenPurge(s, n: 8, purged: 5)
        XCTAssertEqual(try pass(s).orphansTrashed, 0)
        XCTAssertTrue(try rows(s).values.allSatisfy { $0.deletedAt == nil })

        let empty = try stores()
        try ingestThenPurge(empty, n: 2, purged: 2)
        XCTAssertEqual(try pass(empty).orphansTrashed, 0, "an empty store is never read as all purged")
    }

    func testTheOrphanSweepNeverTouchesTheVault() throws {
        // A trashed row keeps its exported file (C156); the sweep only sets deletedAt.
        let s = try stores()
        let ids = try ingestThenPurge(s, n: 8, purged: 1)
        let vaultFile = scratch.appendingPathComponent("vault/Note.md")
        try FileManager.default.createDirectory(at: vaultFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "exported".write(to: vaultFile, atomically: true, encoding: .utf8)
        let row = try XCTUnwrap(try rows(s)[ids[0].uuidString])
        row.exportStatus = .done
        let workingPath = row.path

        try pass(s)

        XCTAssertNotNil(row.deletedAt)
        XCTAssertTrue(FileManager.default.fileExists(atPath: vaultFile.path))
        XCTAssertEqual(row.exportStatus, .done)
        XCTAssertEqual(row.path, workingPath)
        if !workingPath.isEmpty { XCTAssertTrue(FileManager.default.fileExists(atPath: workingPath), "the working folder stays for Restore") }
    }
}
