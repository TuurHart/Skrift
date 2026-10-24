import XCTest
import SwiftData
import Foundation

/// Q364 (D186, D191, C278, C281): the Mac's reconcile pass runs on every launch, every
/// Cmd-Tab and every CloudKit import burst, on the main actor. At 2,000 notes the old pass
/// faulted every monologue's audio blob (the late-diarization heal fetched full asset rows
/// for any note without diarization, which is every monologue forever), ran two unindexed
/// `Memo` lookups per local row (`MacMemoAuthor.backfill` + `reflectTranscripts`), and
/// re-serialised every note's metadata JSON. These counters hold the line: a steady-state
/// pass over 2,000 already-ingested monologues fetches no blob, does O(1) `Memo` fetches,
/// re-serialises nothing, and writes nothing. Never loosen these to pass (D186).
@MainActor
final class MacReconcileWorkTests: XCTestCase {

    private let noteCount = 2_000

    private lazy var upload = FileManager.default.temporaryDirectory
            .appendingPathComponent("q364_\(UUID().uuidString)", isDirectory: true)

    override func tearDown() {
        try? FileManager.default.removeItem(at: upload)
        super.tearDown()
    }

    private func stores() throws -> (cloud: ModelContext, local: ModelContext) {
        let cloud = try ModelContainer(for: Memo.self, MemoAsset.self, MemoEnhancement.self, MemoEditHead.self,
                                       configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let local = try ModelContainer(for: PipelineFile.self,
                                       configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        return (ModelContext(cloud), ModelContext(local))
    }

    /// 2,000 rated phone monologues: trusted transcript, an audio asset, no diarization,
    /// no word timings, some metadata. The shape every real library is mostly made of.
    private func seedMonologues(_ cloud: ModelContext, count: Int = 2_000) throws {
        let meta = Data(#"{"dayPeriod":"morning","steps":1200}"#.utf8)
        for i in 0..<count {
            let memo = Memo(id: UUID(), audioFilename: "memo_\(i).m4a",
                            recordedAt: Date(timeIntervalSince1970: 1_700_000_000 + Double(i)),
                            transcript: "Words of note \(i).", transcriptStatus: .done,
                            transcriptConfidence: 0.9, significance: 0.5,
                            metadataData: meta, recordingDeviceID: "iphone-test")
            cloud.insert(memo)
            cloud.insert(MemoAsset(memoID: memo.id, kind: MemoAsset.Kind.audio,
                                   filename: memo.audioFilename, blob: Data("AUDIO\(i)".utf8)))
        }
        try cloud.save()
    }

    private func pass(_ s: (cloud: ModelContext, local: ModelContext)) throws -> ReconcileV2.PassOutcome {
        V2.pass(s.cloud, into: s.local, device: "mac-test", outputDir: upload)
    }

    /// The first pass ingests everything (blobs are needed then). Every pass after it, with
    /// nothing changed, must stay off the blobs, off per-row Memo lookups, and off the JSON.
    func testSteadyStatePassOver2000MonologuesFetchesNoBlobAndO1MemoFetches() throws {
        let s = try stores()
        try seedMonologues(s.cloud)

        let first = try pass(s)
        XCTAssertEqual(first.sweep.created, noteCount, "the first pass ingests every rated memo")
        XCTAssertEqual(try s.local.fetchCount(FetchDescriptor<PipelineFile>()), noteCount)

        ReconcileWork.reset()
        let second = try pass(s)
        let work = ReconcileWork.counts

        XCTAssertEqual(second.sweep.created, 0)
        XCTAssertEqual(second.sweep.updatedIDs, [], "nothing changed, nothing reflected")
        XCTAssertEqual(work.assetBlobFetches, 0,
                       "a steady-state pass must never fetch full MemoAsset rows (their blobs fault in)")
        XCTAssertLessThanOrEqual(work.memoFetches, 2,
                                 "O(1) Memo fetches per pass, not one (or two) per local row")
        XCTAssertLessThanOrEqual(work.assetIndexFetches, 1,
                                 "at most one blob-free asset index fetch per pass")
        XCTAssertEqual(work.metadataSerialisations, 0,
                       "unchanged metadata is not re-parsed and re-serialised every pass")
    }

    /// C281: a pass with no data change writes nothing — no save, no dirty context.
    func testSecondPassWithNoChangeWritesNothing() throws {
        let s = try stores()
        try seedMonologues(s.cloud)
        _ = try pass(s)
        _ = try pass(s)   // settle anything the first pass legitimately left to do

        ReconcileWork.reset()
        let third = try pass(s)
        XCTAssertEqual(third.sweep.created, 0)
        XCTAssertEqual(third.sweep.updatedIDs, [])
        XCTAssertEqual(third.authored, 0)
        XCTAssertEqual(third.reflectedTranscripts, 0)
        XCTAssertEqual(ReconcileWork.counts.saves, 0, "a no-change pass saves nothing")
        XCTAssertFalse(s.local.hasChanges, "a no-change pass leaves the pipeline store clean")
        XCTAssertFalse(s.cloud.hasChanges, "a no-change pass leaves the cloud store clean")
    }

    /// The pass hands back the memo snapshot it fetched, so the lifecycle sweep and the
    /// Connections snapshot reuse it instead of fetching every Memo again.
    func testPassReturnsItsMemoSnapshot() throws {
        let s = try stores()
        try seedMonologues(s.cloud, count: 50)
        let outcome = try pass(s)
        XCTAssertEqual(outcome.snapshot.memos.count, 50)
    }

    /// The short-circuit must not cost the heal: a `diar` asset that lands AFTER ingest is
    /// still adopted on the next pass, and only that note's assets are read.
    func testLateDiarizationStillAdoptedWithoutTouchingOtherBlobs() throws {
        let s = try stores()
        try seedMonologues(s.cloud, count: 50)
        _ = try pass(s)

        let target = try XCTUnwrap(try s.cloud.fetch(FetchDescriptor<Memo>()).first)
        let blob = Data(#"{"segments":[{"speaker":0,"start":0,"end":1.5},{"speaker":1,"start":1.5,"end":3}]}"#.utf8)
        s.cloud.insert(MemoAsset(memoID: target.id, kind: MemoAsset.Kind.diarization,
                                 filename: "diar.json", blob: blob))
        try s.cloud.save()

        ReconcileWork.reset()
        let outcome = try pass(s)
        XCTAssertEqual(outcome.sweep.updatedIDs, [target.id.uuidString])
        XCTAssertEqual(ReconcileWork.counts.assetBlobFetches, 1, "only the one note with a late asset reads blobs")
        let pf = try XCTUnwrap(try s.local.fetch(FetchDescriptor<PipelineFile>()).first { $0.id == target.id.uuidString })
        XCTAssertEqual(pf.diarizationSegments.count, 2)
    }

    /// A metadata change on the phone still reaches the row (the cache must not hide it).
    func testChangedMetadataStillReflects() throws {
        let s = try stores()
        try seedMonologues(s.cloud, count: 50)
        _ = try pass(s)

        let target = try XCTUnwrap(try s.cloud.fetch(FetchDescriptor<Memo>()).first)
        target.metadataData = Data(#"{"dayPeriod":"evening","steps":9}"#.utf8)
        try s.cloud.save()

        let outcome = try pass(s)
        XCTAssertEqual(outcome.sweep.updatedIDs, [target.id.uuidString])
        let pf = try XCTUnwrap(try s.local.fetch(FetchDescriptor<PipelineFile>()).first { $0.id == target.id.uuidString })
        let json = String(decoding: try XCTUnwrap(pf.audioMetadataJSON), as: UTF8.self)
        XCTAssertTrue(json.contains("evening"), json)
    }
}
