import XCTest
import SwiftData
import Foundation

/// 8d tests for the reconcile sweep (`MemoCloudReconciler.sweep`): it pulls every eligible
/// synced Memo (+ assets) from the CloudKit store into the local pipeline store, dedups on a
/// repeat sweep, and honors the significance gate.
@MainActor
final class MemoCloudReconcilerTests: XCTestCase {

    /// In-memory mirror of the CloudKit Memo store.
    private func cloudContext() throws -> ModelContext {
        let c = try ModelContainer(for: Memo.self, MemoAsset.self, MemoEnhancement.self,
                                   configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        return ModelContext(c)
    }

    /// Working folders go to a TEMP dir, never the app's real audio-output directory —
    /// these tests had been materialising ingest folders into the live Dev data folder.
    private lazy var upload = UploadService(
        outputDir: FileManager.default.temporaryDirectory
            .appendingPathComponent("mcr_\(UUID().uuidString)", isDirectory: true))

    override func tearDown() {
        try? FileManager.default.removeItem(at: upload.outputDir)
        super.tearDown()
    }

    /// In-memory mirror of the local pipeline store.
    private func localContext() throws -> ModelContext {
        let c = try ModelContainer(for: PipelineFile.self,
                                   configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        return ModelContext(c)
    }

    /// Seed a synced memo + its audio asset into the cloud context.
    private func seedMemo(_ cloud: ModelContext, significance: Double, bytes: String = "AUDIO") {
        let memo = Memo(id: UUID(), audioFilename: "memo_\(UUID().uuidString).m4a", recordedAt: Date(),
                        transcript: "hi", transcriptStatus: .done, transcriptConfidence: 0.9,
                        significance: significance)
        let asset = MemoAsset(memoID: memo.id, kind: MemoAsset.Kind.audio,
                              filename: MemoCloudIngest.audioFilename(for: memo), blob: Data(bytes.utf8))
        cloud.insert(memo)
        cloud.insert(asset)
    }

    private func pipelineCount(_ ctx: ModelContext) -> Int {
        (try? ctx.fetchCount(FetchDescriptor<PipelineFile>())) ?? 0
    }

    func testSweepIngestsEligibleMemos() throws {
        let cloud = try cloudContext(), local = try localContext()
        seedMemo(cloud, significance: 0.5)
        seedMemo(cloud, significance: 0.8)
        seedMemo(cloud, significance: 0)     // gated out (flag-to-send)
        try cloud.save()

        let created = MemoCloudReconciler.sweep(from: cloud, into: local, upload: upload).created
        XCTAssertEqual(created, 2, "two rated memos ingest; the significance-0 one syncs but is skipped")
        XCTAssertEqual(pipelineCount(local), 2)
    }

    func testSecondSweepDedups() throws {
        let cloud = try cloudContext(), local = try localContext()
        seedMemo(cloud, significance: 0.5)
        try cloud.save()

        XCTAssertEqual(MemoCloudReconciler.sweep(from: cloud, into: local, upload: upload).created, 1)
        // A second reconcile (foreground/import) must not duplicate already-ingested memos.
        XCTAssertEqual(MemoCloudReconciler.sweep(from: cloud, into: local, upload: upload).created, 0)
        XCTAssertEqual(pipelineCount(local), 1)
    }

    // MARK: - Same-id duplicate rows (the 2026-07-12 clone incident, Mac side)

    /// Seed one memo row with explicit id/content into the cloud context.
    private func seedRow(_ cloud: ModelContext, id: UUID, transcript: String,
                         deletedAt: Date? = nil, withAsset: Bool = true) {
        let memo = Memo(id: id, audioFilename: "memo_\(id.uuidString).m4a",
                        recordedAt: Date(timeIntervalSince1970: 1_000_000),
                        transcript: transcript, transcriptStatus: .done,
                        transcriptConfidence: 0.9, significance: 0.5, deletedAt: deletedAt)
        cloud.insert(memo)
        if withAsset {
            cloud.insert(MemoAsset(memoID: memo.id, kind: MemoAsset.Kind.audio,
                                   filename: MemoCloudIngest.audioFilename(for: memo),
                                   blob: Data("AUDIO".utf8)))
        }
    }

    /// Two ALIVE same-id rows with DIVERGING content (the pair the phone deliberately
    /// never auto-heals): the sweep must reconcile against ONE keeper, and a repeat
    /// sweep must be a no-op — before the canonical-rows fix the two rows took turns
    /// rewriting the single PipelineFile every sweep (recompile + re-export churn).
    func testDivergentSameIDRowsDoNotChurn() throws {
        let cloud = try cloudContext(), local = try localContext()
        let id = UUID()
        seedRow(cloud, id: id, transcript: "short")
        seedRow(cloud, id: id, transcript: "the considerably longer keeper transcript", withAsset: false)
        try cloud.save()

        let first = MemoCloudReconciler.sweep(from: cloud, into: local, upload: upload)
        XCTAssertEqual(first.created, 1, "one id → one PipelineFile")
        XCTAssertEqual(pipelineCount(local), 1)
        let pf = try XCTUnwrap((try? local.fetch(FetchDescriptor<PipelineFile>()))?.first)
        XCTAssertEqual(pf.transcript, "the considerably longer keeper transcript",
                       "the keeper (most content) wins, not fetch order")

        let second = MemoCloudReconciler.sweep(from: cloud, into: local, upload: upload)
        XCTAssertEqual(second.created, 0)
        XCTAssertTrue(second.updatedIDs.isEmpty,
                      "repeat sweep is a NO-OP — no flip-flop between the divergent rows")
        XCTAssertEqual(pf.transcript, "the considerably longer keeper transcript")
    }

    /// A healed pair (alive keeper + trashed, blob-detached clone) reconciles to the
    /// keeper's content — the trashed clone never shadows it.
    func testTrashedCloneNeverShadowsTheKeeper() throws {
        let cloud = try cloudContext(), local = try localContext()
        let id = UUID()
        seedRow(cloud, id: id, transcript: "clone (already trashed by the phone)", deletedAt: Date(), withAsset: false)
        seedRow(cloud, id: id, transcript: "keeper")
        try cloud.save()

        let outcome = MemoCloudReconciler.sweep(from: cloud, into: local, upload: upload)
        XCTAssertEqual(outcome.created, 1)
        let pf = try XCTUnwrap((try? local.fetch(FetchDescriptor<PipelineFile>()))?.first)
        XCTAssertEqual(pf.transcript, "keeper")
        XCTAssertTrue(MemoCloudReconciler.sweep(from: cloud, into: local,
                                                upload: upload).updatedIDs.isEmpty)
    }

    // MARK: - Two memos, one audioFilename (the reflected=4 churn, 2026-07-27)

    /// The phone can mint two memos sharing an `audioFilename` — an audiobook quote capture
    /// inherits the source memo's name. Each deserves its OWN PipelineFile. Before the fix
    /// the filename arm handed the second memo the FIRST memo's row, and the two then
    /// overwrote each other on alternating sweeps forever (bookTitle appearing/vanishing,
    /// duration + recordedAt swapping), re-exporting the note every pass.
    func testTwoMemosSharingAFilenameGetSeparateRows() throws {
        let cloud = try cloudContext(), local = try localContext()
        let shared = "memo_\(UUID().uuidString).m4a"
        for transcript in ["the plain memo", "the audiobook quote capture"] {
            let m = Memo(id: UUID(), audioFilename: shared, recordedAt: Date(),
                         transcript: transcript, transcriptStatus: .done,
                         transcriptConfidence: 0.9, significance: 0.5)
            cloud.insert(m)
            cloud.insert(MemoAsset(memoID: m.id, kind: MemoAsset.Kind.audio,
                                   filename: shared, blob: Data("AUDIO".utf8)))
        }
        try cloud.save()

        XCTAssertEqual(MemoCloudReconciler.sweep(from: cloud, into: local,
                                                 upload: upload).created, 2,
                       "a shared filename must not collapse two distinct memos into one row")
        XCTAssertEqual(pipelineCount(local), 2)

        // …and the steady state is silent: neither row is claimed by the other's memo.
        let second = MemoCloudReconciler.sweep(from: cloud, into: local, upload: upload)
        XCTAssertEqual(second.created, 0)
        XCTAssertTrue(second.updatedIDs.isEmpty,
                      "no ping-pong — the sweep settles instead of reflecting forever")
    }

    /// The filename arm still does its job: a LEGACY Bonjour-era row (random, non-UUID id)
    /// is matched by filename so a CloudKit re-ingest dedups against it.
    func testLegacyNonUUIDRowIsStillMatchedByFilename() throws {
        let cloud = try cloudContext(), local = try localContext()
        let id = UUID()
        let filename = "memo_\(id.uuidString).m4a"
        let legacy = PipelineFile(id: "bonjour-random-1234", filename: filename)
        legacy.transcript = "ingested over the old HTTP path"
        legacy.transcribeStatus = .done
        local.insert(legacy)
        let m = Memo(id: id, audioFilename: filename, recordedAt: Date(),
                     transcript: "ingested over the old HTTP path", transcriptStatus: .done,
                     transcriptConfidence: 0.9, significance: 0.5)
        cloud.insert(m)
        cloud.insert(MemoAsset(memoID: m.id, kind: MemoAsset.Kind.audio,
                               filename: filename, blob: Data("AUDIO".utf8)))
        try cloud.save()

        XCTAssertEqual(MemoCloudReconciler.sweep(from: cloud, into: local,
                                                 upload: upload).created, 0,
                       "legacy row still claimed by filename — no duplicate")
        XCTAssertEqual(pipelineCount(local), 1)
    }

    // MARK: - Late word-timings asset heal (the 2026-07-25 karaoke-dead note)

    /// CloudKit delivered the `wordTimings` asset 10½ hours after the Memo record; ingest
    /// had already run with no timings and nothing ever healed the row — karaoke-dead on
    /// the Mac while the phone/iPad played the same note fine.
    func testLateWordTimingsAssetHealsOnNextSweep() throws {
        let cloud = try cloudContext(), local = try localContext()
        seedMemo(cloud, significance: 0.5)
        try cloud.save()
        XCTAssertEqual(MemoCloudReconciler.sweep(from: cloud, into: local, upload: upload).created, 1)
        let pf = try XCTUnwrap((try? local.fetch(FetchDescriptor<PipelineFile>()))?.first)
        XCTAssertTrue(pf.wordTimings.isEmpty, "the asset hadn't synced when ingest ran")

        // The asset lands later (CloudKit syncs asset rows independently of the memo).
        let memo = try XCTUnwrap((try? cloud.fetch(FetchDescriptor<Memo>()))?.first)
        let words = [WordTiming(word: "hello", start: 0, end: 0.4),
                     WordTiming(word: "there", start: 0.4, end: 0.9)]
        cloud.insert(MemoAsset(memoID: memo.id, kind: MemoAsset.Kind.wordTimings,
                               filename: "wt_\(memo.id.uuidString).json",
                               blob: try JSONEncoder().encode(words)))
        try cloud.save()

        let outcome = MemoCloudReconciler.sweep(from: cloud, into: local, upload: upload)
        XCTAssertEqual(pf.wordTimings, words, "the next sweep adopts the late asset")
        XCTAssertEqual(outcome.updatedIDs, [pf.id], "heal reports the row so the open note re-renders")

        XCTAssertTrue(MemoCloudReconciler.sweep(from: cloud, into: local,
                                                upload: upload).updatedIDs.isEmpty,
                      "idempotent — a healed row is a steady-state no-op")
    }

    /// The Mac's own ASR timings (an untrusted memo the Mac re-transcribed) must never be
    /// clobbered by a late phone asset — the empty-guard is the contract.
    func testLateTimingsNeverClobberMacASRTimings() throws {
        let cloud = try cloudContext(), local = try localContext()
        seedMemo(cloud, significance: 0.5)
        try cloud.save()
        _ = MemoCloudReconciler.sweep(from: cloud, into: local, upload: upload)
        let pf = try XCTUnwrap((try? local.fetch(FetchDescriptor<PipelineFile>()))?.first)
        let macOwn = [WordTiming(word: "mac", start: 0, end: 0.5)]
        pf.wordTimings = macOwn   // BatchRunner wrote the Mac's own run

        let memo = try XCTUnwrap((try? cloud.fetch(FetchDescriptor<Memo>()))?.first)
        cloud.insert(MemoAsset(memoID: memo.id, kind: MemoAsset.Kind.wordTimings,
                               filename: "wt_\(memo.id.uuidString).json",
                               blob: try JSONEncoder().encode([WordTiming(word: "phone", start: 0, end: 1)])))
        try cloud.save()

        _ = MemoCloudReconciler.sweep(from: cloud, into: local, upload: upload)
        XCTAssertEqual(pf.wordTimings, macOwn, "existing timings win; the heal only fills a hole")
    }

    /// The diarization twin: a late `diar` asset is adopted the same way, so the Mac can
    /// still enroll a speaker's voice from a phone-diarized conversation.
    func testLateDiarizationAssetHealsOnNextSweep() throws {
        let cloud = try cloudContext(), local = try localContext()
        seedMemo(cloud, significance: 0.5)
        try cloud.save()
        _ = MemoCloudReconciler.sweep(from: cloud, into: local, upload: upload)
        let pf = try XCTUnwrap((try? local.fetch(FetchDescriptor<PipelineFile>()))?.first)
        XCTAssertTrue(pf.diarizationSegments.isEmpty)

        let memo = try XCTUnwrap((try? cloud.fetch(FetchDescriptor<Memo>()))?.first)
        let segs = [DiarizedSegment(speaker: 0, start: 0, end: 1.2),
                    DiarizedSegment(speaker: 1, start: 1.2, end: 2.5)]
        cloud.insert(MemoAsset(memoID: memo.id, kind: MemoAsset.Kind.diarization,
                               filename: "diar_\(memo.id.uuidString).json",
                               blob: try JSONEncoder().encode(
                                   DiarizationData(segments: segs, slotNames: ["0": "Tuur"]))))
        try cloud.save()

        let outcome = MemoCloudReconciler.sweep(from: cloud, into: local, upload: upload)
        XCTAssertEqual(pf.diarizationSegments, segs, "the next sweep adopts the late diar asset")
        XCTAssertEqual(outcome.updatedIDs, [pf.id])
        XCTAssertTrue(MemoCloudReconciler.sweep(from: cloud, into: local,
                                                upload: upload).updatedIDs.isEmpty,
                      "idempotent")
    }

    /// A corrupt blob must be ignored — no adopt, no crash, and the row stays healable.
    func testGarbageTimingsBlobIsIgnored() throws {
        let cloud = try cloudContext(), local = try localContext()
        seedMemo(cloud, significance: 0.5)
        try cloud.save()
        _ = MemoCloudReconciler.sweep(from: cloud, into: local, upload: upload)
        let pf = try XCTUnwrap((try? local.fetch(FetchDescriptor<PipelineFile>()))?.first)

        let memo = try XCTUnwrap((try? cloud.fetch(FetchDescriptor<Memo>()))?.first)
        cloud.insert(MemoAsset(memoID: memo.id, kind: MemoAsset.Kind.wordTimings,
                               filename: "wt_\(memo.id.uuidString).json",
                               blob: Data("not json".utf8)))
        try cloud.save()

        let outcome = MemoCloudReconciler.sweep(from: cloud, into: local, upload: upload)
        XCTAssertTrue(pf.wordTimings.isEmpty)
        XCTAssertTrue(outcome.updatedIDs.isEmpty, "a failed decode is not an update")
    }

    // MARK: - The rate→row handoff (Tuur's two stranded notes, 2026-08-19)

    /// Seed a TYPED note (no audio, no sharedContent) — the shape both the Mac's ✎ verb
    /// and the iPad's mint.
    @discardableResult
    private func seedTypedMemo(_ cloud: ModelContext, text: String, significance: Double) throws -> Memo {
        let memo = try Memo.newTyped(into: cloud)
        memo.transcript = text
        memo.transcriptUserEdited = true
        memo.significance = significance
        try cloud.save()
        return memo
    }

    /// A note typed on the Mac, then RATED, must arrive in the pipeline list. It used to
    /// reach no list section at all: the ingest silently produced no row (text-only memos
    /// fell through `UploadService.prepare`), and rating it removed it from the quiet rows
    /// (those are the unrated ones). Invisible, while three copies sat safe in the store.
    func testRatedTypedNoteSweepsIntoARow() throws {
        let cloud = try cloudContext(), local = try localContext()
        try seedTypedMemo(cloud, text: "Mats was tien jaar.", significance: 0.1)

        let outcome = MemoCloudReconciler.sweep(from: cloud, into: local, upload: upload)
        XCTAssertEqual(outcome.created, 1, "the rating IS the handoff — it must produce a row")
        let pf = try XCTUnwrap((try? local.fetch(FetchDescriptor<PipelineFile>()))?.first)
        XCTAssertEqual(pf.transcript, "Mats was tien jaar.")
        XCTAssertEqual(pf.sourceType, .note)
        XCTAssertEqual(MemoCloudReconciler.sweep(from: cloud, into: local, upload: upload).created, 0,
                       "and the next sweep dedups it like any other row")
    }

    /// The invariant behind the symptom: after a sweep, NO rated live memo may be left
    /// without a row. A memo in that state renders in neither list section — the Mac's
    /// version of a note that looks deleted but isn't.
    func testNoRatedMemoIsLeftStranded() throws {
        let cloud = try cloudContext(), local = try localContext()
        try seedTypedMemo(cloud, text: "typed + rated", significance: 0.1)
        seedMemo(cloud, significance: 0.5)                       // ordinary audio memo
        let unrated = try seedTypedMemo(cloud, text: "not judged yet", significance: 0)
        try cloud.save()

        let outcome = MemoCloudReconciler.sweep(from: cloud, into: local, upload: upload)
        XCTAssertEqual(outcome.stranded, 0, "a rated memo with no row is invisible — never ship one")
        let files = (try? local.fetch(FetchDescriptor<PipelineFile>())) ?? []
        XCTAssertEqual(files.count, 2)
        XCTAssertFalse(files.contains { $0.id == unrated.id.uuidString }, "unrated stays out of the queue")
    }

    /// His polish must come BACK. When the only surviving copy of a Mac-written copy-edit
    /// is the cloud `MemoEnhancement`, the row that ingests afterwards has to adopt it —
    /// the self-echo guard (skip an enhancement THIS device wrote) is right for a row that
    /// already holds the polish locally, and wrong for a row that was just created.
    func testFreshRowAdoptsThisDevicesOwnEnhancement() throws {
        let cloud = try cloudContext(), local = try localContext()
        let memo = try seedTypedMemo(cloud, text: "raw blob without paragraphs", significance: 0.1)
        cloud.insert(MemoEnhancement(memoID: memo.id,
                                     copyedit: "Polished.\n\nWith paragraphs.",
                                     title: "Mats", summary: "A boy and the sea.",
                                     enhancedByDeviceID: DeviceID.current()))
        try cloud.save()

        _ = MemoCloudReconciler.sweep(from: cloud, into: local,
                                      thisDeviceID: DeviceID.current(), upload: upload)
        let pf = try XCTUnwrap((try? local.fetch(FetchDescriptor<PipelineFile>()))?.first)
        XCTAssertEqual(pf.enhancedCopyedit, "Polished.\n\nWith paragraphs.",
                       "the already-written polish surfaces with the note")
        XCTAssertEqual(pf.enhancedTitle, "Mats")
        XCTAssertEqual(pf.enhancedSummary, "A boy and the sea.")
    }

    /// …and the guard still holds where it belongs: on an EXISTING row, this device's own
    /// enhancement is its own echo and must not be re-applied over local work.
    func testExistingRowStillIgnoresItsOwnEnhancementEcho() throws {
        let cloud = try cloudContext(), local = try localContext()
        seedMemo(cloud, significance: 0.5)
        try cloud.save()
        _ = MemoCloudReconciler.sweep(from: cloud, into: local,
                                      thisDeviceID: DeviceID.current(), upload: upload)
        let pf = try XCTUnwrap((try? local.fetch(FetchDescriptor<PipelineFile>()))?.first)
        pf.enhancedCopyedit = "the Mac's local, newer copy"

        let memo = try XCTUnwrap((try? cloud.fetch(FetchDescriptor<Memo>()))?.first)
        cloud.insert(MemoEnhancement(memoID: memo.id, copyedit: "a stale echo of my own write",
                                     enhancedByDeviceID: DeviceID.current()))
        try cloud.save()

        _ = MemoCloudReconciler.sweep(from: cloud, into: local,
                                      thisDeviceID: DeviceID.current(), upload: upload)
        XCTAssertEqual(pf.enhancedCopyedit, "the Mac's local, newer copy", "no echo clobber")
    }
}
