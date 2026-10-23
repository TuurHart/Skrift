import XCTest
import SwiftData
import Foundation

/// Q510: reconcile v2 covers the whole pass, not only the sweep — the identical-text case of R44,
/// the orphan trash with Q487's refusals (C157), the Mac's own memos (author backfill + transcript
/// reflect, Q397 / C245), the background first-enable ingest's two halves, and C185's order.
@MainActor
final class ReconcileV2PassTests: XCTestCase {

    private var cloudContainer: ModelContainer!
    private var localContainer: ModelContainer!
    private var cloud: ModelContext!
    private var local: ModelContext!
    private var out: URL!
    private let device = "mac-1"
    private let t0 = Date(timeIntervalSince1970: 1_767_225_600)

    override func setUpWithError() throws {
        cloudContainer = try ModelContainer(for: Memo.self, MemoAsset.self, MemoEnhancement.self,
                                            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none))
        localContainer = try ModelContainer(for: PipelineFile.self,
                                            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        cloud = ModelContext(cloudContainer)
        local = ModelContext(localContainer)
        out = FileManager.default.temporaryDirectory.appendingPathComponent("q510-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: out) }

    private func ctx(inFlight: Set<UUID> = []) -> ReconcileV2.Context {
        .init(people: [], author: "A", thisDeviceID: device, now: t0, outputDir: out.appendingPathComponent("out"), inFlight: inFlight)
    }

    @discardableResult
    private func pass(firstImportDone: Bool = true, inFlight: Set<UUID> = []) -> ReconcileV2.PassOutcome {
        ReconcileV2.pass(cloud: cloud, local: local, context: ctx(inFlight: inFlight), firstImportDone: firstImportDone)
    }

    private func rows() throws -> [PipelineFile] { try local.fetch(FetchDescriptor<PipelineFile>()) }

    @discardableResult
    private func voiceMemo(_ words: String = "Kiln loaded.") throws -> Memo {
        let memo = Memo(id: UUID(), recordedAt: t0, transcript: words, transcriptStatus: .done,
                        transcriptConfidence: 0.95, significance: 0.6, createdAt: t0)
        memo.audioFilename = "memo_\(memo.id.uuidString).m4a"
        cloud.insert(memo)
        cloud.insert(MemoAsset(memoID: memo.id, kind: MemoAsset.Kind.audio, filename: memo.audioFilename, blob: Data("AUDIO".utf8)))
        try cloud.save()
        return memo
    }

    // MARK: - R44: identical text, later stamp

    func testALaterStampedPhonePolishWithIdenticalTextIsNotRefused_R44() throws {
        let memo = try voiceMemo()
        cloud.insert(MemoEnhancement(memoID: memo.id, copyedit: "Kiln loaded.", enhancedByDeviceID: "phone-1", enhancedAt: t0))
        try cloud.save()
        pass()
        let row = try XCTUnwrap(try rows().first)
        // The phone polishes again: the SAME words, a later stamp. Nothing to adopt…
        let e = try XCTUnwrap(try cloud.fetch(FetchDescriptor<MemoEnhancement>()).first)
        e.enhancedAt = t0.addingTimeInterval(3600)
        try cloud.save()
        let before = row.syncedSourceEditedAt
        let outcome = pass()
        XCTAssertEqual(outcome.sweep.updatedIDs, [], "identical words are no re-export")
        XCTAssertEqual(outcome.sweep.watermarked, 1)
        XCTAssertGreaterThan(try XCTUnwrap(row.syncedSourceEditedAt), try XCTUnwrap(before), "…but it was SEEN")
        // …so the Mac's next polish lands instead of being refused as "newer, unseen".
        row.enhancedCopyedit = "The kiln is loaded."
        XCTAssertEqual(try ReconcileV2.Writers.upsertEnhancement(for: row, into: cloud, deviceID: device, now: t0), .written)
        XCTAssertEqual(try cloud.fetch(FetchDescriptor<MemoEnhancement>()).first?.copyedit, "The kiln is loaded.")
        XCTAssertEqual(pass().sweep.watermarked, 0, "settled")
    }

    // MARK: - C157 + Q487: orphans

    private func linkedRows(_ n: Int) throws -> [Memo] {
        let memos = try (0..<n).map { _ in try voiceMemo() }
        pass()
        XCTAssertEqual(try rows().count, n)
        return memos
    }

    func testARowWhoseMemoWasPurgedGoesToTheTrash_C157() throws {
        let memos = try linkedRows(8)
        cloud.delete(memos[0])
        try cloud.save()
        XCTAssertEqual(pass(firstImportDone: false).orphansTrashed, 0, "before the first import, a missing memo may not have arrived")
        XCTAssertEqual(pass().orphansTrashed, 1)
        let gone = try XCTUnwrap(try rows().first { $0.id == memos[0].id.uuidString })
        XCTAssertEqual(gone.deletedAt, t0)
        XCTAssertEqual(pass().orphansTrashed, 0, "a trashed row is not trashed again")
    }

    func testMoreThanAQuarterAtOnceIsADifferentStoreNotAPurge_Q487() throws {
        let memos = try linkedRows(8)
        for m in memos.prefix(3) { cloud.delete(m) }   // 3 of 8 > a quarter, and > 2
        try cloud.save()
        XCTAssertEqual(pass().orphansTrashed, 0)
        XCTAssertTrue(try rows().allSatisfy { $0.deletedAt == nil })
        for m in memos.dropFirst(3) { cloud.delete(m) }  // an empty store
        try cloud.save()
        XCTAssertEqual(pass().orphansTrashed, 0)
    }

    func testTwoAtOnceAndInFlightRows_Q487() throws {
        let memos = try linkedRows(3)
        cloud.delete(memos[0]); cloud.delete(memos[1])   // 2 of 3: over a quarter, but only two
        try cloud.save()
        XCTAssertEqual(pass(inFlight: [memos[1].id]).orphansTrashed, 1, "an in-flight ingest is never an orphan")
    }

    // MARK: - the Mac's own memos

    /// A take this Mac recorded: a local row with real audio, no memo yet.
    private func macTake(words: String? = nil) throws -> PipelineFile {
        let id = UUID().uuidString
        let folder = out.appendingPathComponent("\(id)_take.m4a")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let audio = folder.appendingPathComponent("original.m4a")
        try Data("TAKE".utf8).write(to: audio)
        let row = PipelineFile(id: id, filename: "memo_\(UUID().uuidString).m4a", path: audio.path, size: 4, sourceType: .audio)
        row.isLocalRecording = true
        row.uploadedAt = t0
        if let words { row.transcript = words; row.transcribeStatus = .done }
        local.insert(row)
        try local.save()
        return row
    }

    func testATakeGetsItsMemoAfterTheFirstImportAndItsWordsLater_Q397_C245() throws {
        let row = try macTake()
        XCTAssertEqual(pass(firstImportDone: false).authored, 0, "no authoring before the first import")
        XCTAssertEqual(pass().authored, 1)
        let id = try XCTUnwrap(UUID(uuidString: row.id))
        let memo = try XCTUnwrap(try cloud.fetch(FetchDescriptor<Memo>(predicate: #Predicate { $0.id == id })).first)
        XCTAssertEqual(memo.significance, 0, "a recording stays unrated (D159)")
        XCTAssertEqual(memo.recordingDeviceID, device)
        XCTAssertEqual(memo.recordedAt, t0)
        XCTAssertTrue(memo.audioFilename.hasSuffix(".m4a"))
        XCTAssertEqual(try cloud.fetchCount(FetchDescriptor<MemoAsset>(predicate: #Predicate { $0.memoID == id })), 1)
        XCTAssertNil(memo.transcript)
        XCTAssertEqual(pass().authored, 0, "idempotent")

        // The Mac's own ASR lands: its words and timings reach the memo once, no edit-time bump.
        row.transcript = "The take's words."
        row.wordTimings = [WordTiming(word: "The", start: 0, end: 0.2)]
        row.transcribeStatus = .done
        let edited = memo.lastEditedAt
        XCTAssertEqual(pass().reflectedTranscripts, 1)
        XCTAssertEqual(memo.transcript, "The take's words.")
        XCTAssertEqual(memo.transcriptConfidence, 1.0)
        XCTAssertEqual(memo.lastEditedAt, edited)
        let kind = MemoAsset.Kind.wordTimings
        XCTAssertEqual(try cloud.fetchCount(FetchDescriptor<MemoAsset>(predicate: #Predicate { $0.memoID == id && $0.kind == kind })), 1)
        XCTAssertEqual(pass().reflectedTranscripts, 0)
    }

    func testAPhoneRowIsNeverAuthoredAndAnotherDevicesMemoNeverReflected_Q397() throws {
        let memo = try voiceMemo("")
        memo.transcript = nil              // not transcribed yet on the phone
        memo.transcriptStatus = .pending
        memo.recordingDeviceID = "phone-1"
        try cloud.save()
        pass()
        let row = try XCTUnwrap(try rows().first)
        XCTAssertFalse(row.isLocalCapture)
        row.transcript = "Mac ASR words."
        row.transcribeStatus = .done
        XCTAssertEqual(pass().reflectedTranscripts, 0, "the phone's memo is the phone's to transcribe")
        XCTAssertEqual(pass().authored, 0)
    }

    // MARK: - the background first-enable ingest

    func testTheDeferredIngestMakesTheSameRowsAsTheInlineOne() async throws {
        let memos = try (0..<3).map { _ in try voiceMemo() }
        let deferred = ReconcileV2.run(cloud: cloud, local: local, context: ctx(), deferNew: true,
                                       fetchMemos: { try $0.fetch(FetchDescriptor<Memo>()) }).outcome
        XCTAssertEqual(Set(deferred.pendingNewIDs), Set(memos.map(\.id)))
        XCTAssertEqual(try rows().count, 0, "nothing written on the main actor")

        // The app's half: blobs read and folders written on a background context…
        let container = cloudContainer!, ids = deferred.pendingNewIDs, dir = out.appendingPathComponent("out")
        let attempts = await Task.detached {
            let bg = ModelContext(container)
            return ids.map { id -> ReconcileV2.Ingest.Attempt in
                let memo = try? bg.fetch(FetchDescriptor<Memo>(predicate: #Predicate { $0.id == id })).first
                let assets = (try? bg.fetch(FetchDescriptor<MemoAsset>(predicate: #Predicate { $0.memoID == id }))) ?? []
                guard let memo else { return .waiting(id) }
                return ReconcileV2.Ingest.attempt(id) { try ReconcileV2.Ingest.prepare(memo, assets: assets, outputDir: dir) }
            }
        }.value
        // …then one synchronous commit on the main actor.
        var outcome = ReconcileV2.Outcome()
        let made = ReconcileV2.Ingest.commit(attempts, memos: try cloud.fetch(FetchDescriptor<Memo>()), enhancements: [:],
                                             into: local, context: ctx(), outcome: &outcome, save: true)
        XCTAssertEqual(made.count, 3)
        XCTAssertEqual(outcome.created, 3)
        XCTAssertEqual(try rows().count, 3)
        XCTAssertTrue(try rows().allSatisfy { $0.transcribeStatus == .done && FileManager.default.fileExists(atPath: $0.path) })
        XCTAssertEqual(pass().sweep.created, 0, "the next sweep finds them settled")
        XCTAssertEqual(pass().sweep.updatedIDs, [])
    }

    // MARK: - C191: the gate the wiring checks before any pass

    func testMacSyncIsOnUnlessHeTurnedItOff_C191() {
        var settings = AppSettings.default
        settings.cloudKitMacSync = nil
        XCTAssertTrue(settings.cloudKitMacSyncEnabled, "never set = on")
        settings.cloudKitMacSync = false
        XCTAssertFalse(settings.cloudKitMacSyncEnabled, "an explicit off is honoured")
    }

    // MARK: - C185 order, C189 re-export

    func testCarriersRunBeforeTheSweepAndExportedRowsReExport_C185_C189() throws {
        let memo = try voiceMemo()
        pass()
        let row = try XCTUnwrap(try rows().first)
        row.exportStatus = .done
        memo.tags = ["glaze"]
        try cloud.save()
        var sawSweepFirst = false
        ReconcileWork.reset()
        let outcome = ReconcileV2.pass(cloud: cloud, local: local, context: ctx(), firstImportDone: true,
                                       carriers: { sawSweepFirst = ReconcileWork.counts.memoFetches > 0 })
        XCTAssertFalse(sawSweepFirst, "names / vocabulary / prompts reconcile before the memo sweep")
        XCTAssertEqual(outcome.reexportIDs, [row.id])
    }
}
