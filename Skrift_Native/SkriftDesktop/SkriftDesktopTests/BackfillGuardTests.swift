import XCTest
import SwiftData
import Foundation

/// Q397 (D203, ICLOUD_MERGE.md A1): the reconcile's backfill may author a `Memo` only for a
/// row this Mac captured (`isLocalCapture`), and only once the cloud store has finished its
/// first CloudKit import. Without it, a fresh `memo_cloud.store` (the Production switch) sees
/// every phone note's row as Memo-less while the download is still running, and uploads a
/// Mac-shaped twin of each one under the phone's id. Synthetic in-memory stores only.
@MainActor
final class BackfillGuardTests: XCTestCase {

    private var scratch: URL!

    private lazy var upload = UploadService(outputDir: scratch.appendingPathComponent("out", isDirectory: true))

    override func setUpWithError() throws {
        scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("q397_\(UUID().uuidString)", isDirectory: true)
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

    private func audioFile(_ name: String) throws -> URL {
        let url = scratch.appendingPathComponent(name)
        try Data("AUDIO".utf8).write(to: url)
        return url
    }

    /// A row the Mac made by ingesting a PHONE memo: its id is the phone's `Memo.id`, it has a
    /// real path, and neither local-capture flag is set.
    private func phoneRow(_ i: Int) throws -> PipelineFile {
        PipelineFile(id: UUID().uuidString, filename: "memo_\(i).m4a",
                     path: try audioFile("phone_\(i).m4a").path, sourceType: .audio)
    }

    /// A row this Mac captured itself (an import; a recording sets `isLocalRecording`).
    private func localImport() throws -> PipelineFile {
        let pf = PipelineFile(id: UUID().uuidString, filename: "dropped.m4a",
                              path: try audioFile("dropped.m4a").path, sourceType: .audio)
        pf.isLocalImport = true
        return pf
    }

    private func pass(_ s: (cloud: ModelContext, local: ModelContext),
                      firstImportDone: Bool) throws -> MemoCloudReconciler.PassOutcome {
        try MemoCloudReconciler.pass(from: s.cloud, into: s.local, thisDeviceID: "mac-test",
                                     upload: upload, firstImportDone: firstImportDone)
    }

    // MARK: - The guard

    /// The Production switch: a fresh, empty cloud store and a pipeline store full of rows
    /// ingested from phone memos. Nothing may be authored, before or after the first import.
    func testFreshStoreWithPhoneRowsAuthorsNothing() throws {
        let s = try stores()
        for i in 0..<5 { s.local.insert(try phoneRow(i)) }
        try s.local.save()

        let before = try pass(s, firstImportDone: false)
        XCTAssertEqual(before.authored, 0)
        let after = try pass(s, firstImportDone: true)
        XCTAssertEqual(after.authored, 0, "a phone row is never re-authored by the Mac, import done or not")
        XCTAssertEqual(try s.cloud.fetchCount(FetchDescriptor<Memo>()), 0, "zero Memos authored")
    }

    /// A Mac capture waits until the first import is done (its Memo may still be downloading).
    func testLocalCaptureBeforeFirstImportAuthorsNothing() throws {
        let s = try stores()
        s.local.insert(try localImport())
        try s.local.save()

        let outcome = try pass(s, firstImportDone: false)
        XCTAssertEqual(outcome.authored, 0)
        XCTAssertEqual(try s.cloud.fetchCount(FetchDescriptor<Memo>()), 0)
    }

    /// After the first import a Mac capture with no Memo is authored, exactly once.
    func testLocalCaptureAfterFirstImportAuthoredOnce() throws {
        let s = try stores()
        let capture = try localImport()
        s.local.insert(capture)
        for i in 0..<3 { s.local.insert(try phoneRow(i)) }
        try s.local.save()

        XCTAssertEqual(try pass(s, firstImportDone: false).authored, 0)
        XCTAssertEqual(try pass(s, firstImportDone: true).authored, 1)
        XCTAssertEqual(try pass(s, firstImportDone: true).authored, 0, "idempotent: never a second Memo")

        let memos = try s.cloud.fetch(FetchDescriptor<Memo>())
        XCTAssertEqual(memos.map(\.id.uuidString), [capture.id], "only the Mac's own capture")
    }

    /// A recording counts as a local capture too.
    func testLocalRecordingIsEligible() throws {
        let pf = PipelineFile(id: UUID().uuidString, filename: "take.m4a",
                              path: try audioFile("take.m4a").path, sourceType: .audio)
        pf.isLocalRecording = true
        XCTAssertTrue(MacMemoAuthor.mayBackfill(pf, firstImportDone: true))
        XCTAssertFalse(MacMemoAuthor.mayBackfill(pf, firstImportDone: false))
        XCTAssertFalse(MacMemoAuthor.mayBackfill(try phoneRow(0), firstImportDone: true))
    }

    /// The pass's default is the safe one: no flag passed, nothing authored.
    func testPassDefaultsToImportNotDone() throws {
        let s = try stores()
        s.local.insert(try localImport())
        try s.local.save()
        let outcome = try MemoCloudReconciler.pass(from: s.cloud, into: s.local,
                                                   thisDeviceID: "mac-test", upload: upload)
        XCTAssertEqual(outcome.authored, 0)
    }

    // MARK: - The persisted first-import flag

    private func makeStore(_ name: String = "memo_cloud.store") throws -> URL {
        let url = scratch.appendingPathComponent(name)
        try Data("sqlite".utf8).write(to: url)
        return url
    }

    func testFlagStartsUnsetAndPersistsOnceMarked() throws {
        let store = try makeStore()
        let stamp = scratch.appendingPathComponent("memo_cloud.first-import.json")
        XCTAssertFalse(CloudFirstImport.isDone(storeURL: store, stampURL: stamp))

        CloudFirstImport.markDone(storeURL: store, stampURL: stamp)
        XCTAssertTrue(FileManager.default.fileExists(atPath: stamp.path), "persisted to disk")
        XCTAssertTrue(CloudFirstImport.isDone(storeURL: store, stampURL: stamp))

        CloudFirstImport.markDone(storeURL: store, stampURL: stamp)   // a later import: no change
        XCTAssertTrue(CloudFirstImport.isDone(storeURL: store, stampURL: stamp))
    }

    /// The stamp belongs to ONE store file. Moving the old store out and letting the app create
    /// a fresh one (ICLOUD_MERGE step 6) must read as "first import not done".
    func testFlagDoesNotCarryOverToAReplacedStore() throws {
        let store = try makeStore()
        let stamp = scratch.appendingPathComponent("memo_cloud.first-import.json")
        CloudFirstImport.markDone(storeURL: store, stampURL: stamp)

        let parked = scratch.appendingPathComponent("merge-from-dev", isDirectory: true)
        try FileManager.default.createDirectory(at: parked, withIntermediateDirectories: true)
        try FileManager.default.moveItem(at: store, to: parked.appendingPathComponent("memo_cloud.store"))
        XCTAssertFalse(CloudFirstImport.isDone(storeURL: store, stampURL: stamp), "no store, not done")

        _ = try makeStore()   // the fresh store the new build creates at the same path
        XCTAssertFalse(CloudFirstImport.isDone(storeURL: store, stampURL: stamp),
                       "a fresh store must wait for its own first import")
        CloudFirstImport.markDone(storeURL: store, stampURL: stamp)
        XCTAssertTrue(CloudFirstImport.isDone(storeURL: store, stampURL: stamp))
    }

    /// No store file yet: marking does nothing (there is no store to vouch for).
    func testMarkWithoutAStoreFileIsANoOp() throws {
        let store = scratch.appendingPathComponent("missing.store")
        let stamp = scratch.appendingPathComponent("memo_cloud.first-import.json")
        CloudFirstImport.markDone(storeURL: store, stampURL: stamp)
        XCTAssertFalse(CloudFirstImport.isDone(storeURL: store, stampURL: stamp))
    }

    /// A corrupt stamp reads as not done, never as done.
    func testCorruptStampReadsNotDone() throws {
        let store = try makeStore()
        let stamp = scratch.appendingPathComponent("memo_cloud.first-import.json")
        try Data("not json".utf8).write(to: stamp)
        XCTAssertFalse(CloudFirstImport.isDone(storeURL: store, stampURL: stamp))
    }
}
