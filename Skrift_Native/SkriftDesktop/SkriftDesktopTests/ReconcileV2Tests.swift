import XCTest
import SwiftData
import Foundation

/// Q429: what reconcile v2 does that one sweep's row golden cannot show — the required
/// differences against v1 (R29, R44, R57), its read failure (R40), the kind rule (C43),
/// duplicates (C48), the pass order and the re-export rule (C185, C189), the writers (C186,
/// C188) and the no-suspension rule (C294). The corpus row diff itself is the Q428 harness
/// (`ReconcileDiffHarnessTests`, engine "v2").
@MainActor
final class ReconcileV2Tests: XCTestCase {

    // Containers are kept alive as long as their contexts.
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
        out = FileManager.default.temporaryDirectory.appendingPathComponent("q429-\(UUID().uuidString)")
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: out) }

    private var ctx: ReconcileV2.Context {
        .init(people: [], author: "A", thisDeviceID: device, now: t0, outputDir: out)
    }

    @discardableResult
    private func sweep() -> ReconcileV2.Outcome { ReconcileV2.sweep(cloud: cloud, local: local, context: ctx) }

    private func row(_ id: UUID) throws -> PipelineFile? {
        let s = id.uuidString
        return try local.fetch(FetchDescriptor<PipelineFile>(predicate: #Predicate { $0.id == s })).first
    }

    /// A rated, trusted voice memo with its audio (and optionally a diarization) asset.
    private func voiceMemo(transcript: String, diarization: [DiarizedSegment]? = nil) throws -> Memo {
        let memo = Memo(id: UUID(), audioFilename: "", recordedAt: t0, transcript: transcript,
                        transcriptStatus: .done, transcriptConfidence: 0.95, significance: 0.6, createdAt: t0)
        memo.audioFilename = "memo_\(memo.id.uuidString).m4a"
        cloud.insert(memo)
        cloud.insert(MemoAsset(memoID: memo.id, kind: MemoAsset.Kind.audio, filename: memo.audioFilename, blob: Data("AUDIO".utf8)))
        if let diarization { try setDiarization(memo, diarization) }
        try cloud.save()
        return memo
    }

    private func setDiarization(_ memo: Memo, _ segments: [DiarizedSegment]) throws {
        let blob = try JSONEncoder().encode(["segments": segments])
        let id = memo.id, kind = MemoAsset.Kind.diarization
        if let a = try cloud.fetch(FetchDescriptor<MemoAsset>(predicate: #Predicate { $0.memoID == id && $0.kind == kind })).first {
            a.blob = blob; a.byteCount = blob.count
        } else {
            cloud.insert(MemoAsset(memoID: id, kind: kind, filename: "diar_\(id.uuidString).json", blob: blob))
        }
        try cloud.save()
    }

    // MARK: - R29: an unchanged store faults no blob

    func testASecondSweepOfAnUnchangedCorpusFetchesNoBlob_R29() throws {
        let root = CorpusSeed.fixtureRoot(file: #filePath)
        try XCTSkipUnless(FileManager.default.fileExists(atPath: root.appendingPathComponent("manifest.json").path))
        try CorpusSeed.seed(from: root, into: cloud, recordingsDirectory: out.appendingPathComponent("rec"))
        XCTAssertGreaterThan(sweep().created, 60)
        ReconcileWork.reset()
        let again = sweep()
        XCTAssertEqual(again.created, 0)
        XCTAssertEqual(again.updatedIDs, [])
        XCTAssertEqual(ReconcileWork.counts.assetBlobFetches, 0,
                       "a settled corpus must not fault a single asset blob (pic-missing-file included)")
        XCTAssertLessThanOrEqual(ReconcileWork.counts.assetIndexFetches, 1, "one blob-free index fetch at most")
    }

    // MARK: - R40: a failed read is a failure

    func testAFailedReadPullsNothingAndSaysSo_R40() throws {
        _ = try voiceMemo(transcript: "Kiln loaded.")
        struct Down: Error {}
        let outcome = ReconcileV2.sweep(cloud: cloud, local: local, context: ctx, fetchMemos: { _ in throw Down() })
        XCTAssertNotNil(outcome.fetchFailure)
        XCTAssertEqual(try local.fetchCount(FetchDescriptor<PipelineFile>()), 0)
        XCTAssertNil(sweep().fetchFailure)
        XCTAssertEqual(try local.fetchCount(FetchDescriptor<PipelineFile>()), 1)
    }

    // MARK: - R44: stamp to stamp, with skew

    func testAFastPhoneClockNeverBlocksTheMacsPolish_R44() throws {
        let memo = try voiceMemo(transcript: "Kiln loaded.")
        // The phone's clock runs an hour fast; its polish arrives stamped in "the future".
        let phoneStamp = Date().addingTimeInterval(3600)
        cloud.insert(MemoEnhancement(memoID: memo.id, copyedit: "Kiln loaded (phone).", title: "Kiln",
                                     enhancedByDeviceID: "phone-1", enhancedAt: phoneStamp))
        try cloud.save()
        sweep()                                   // the row adopts it, watermark = its stamp
        let pf = try XCTUnwrap(try row(memo.id))
        XCTAssertEqual(pf.enhancedCopyedit, "Kiln loaded (phone).")

        // v1 compared the phone's stamp to THIS Mac's clock and refused, forever (deleted at Q432).
        pf.enhancedCopyedit = "Kiln loaded. (Mac pass)"

        // v2 compares stamp to stamp: the row has seen that polish, so the Mac's write lands,
        // stamped after the one it replaces.
        XCTAssertEqual(try ReconcileV2.Writers.upsertEnhancement(for: pf, into: cloud, deviceID: device, now: Date()), .written)
        let e = try XCTUnwrap(try cloud.fetch(FetchDescriptor<MemoEnhancement>()).first)
        XCTAssertEqual(e.copyedit, "Kiln loaded. (Mac pass)")
        XCTAssertGreaterThan(e.enhancedAt, phoneStamp, "every device orders the Mac's write after the phone's")

        // A phone polish the row has NOT seen (beyond the watermark + skew) is not clobbered.
        e.enhancedByDeviceID = "phone-1"
        e.copyedit = "Edited again on the phone."
        e.enhancedAt = (pf.syncedSourceEditedAt ?? t0).addingTimeInterval(ReconcileV2.Writers.skew + 60)
        try cloud.save()
        XCTAssertEqual(try ReconcileV2.Writers.upsertEnhancement(for: pf, into: cloud, deviceID: device), .refusedNewer)
        XCTAssertEqual(try cloud.fetch(FetchDescriptor<MemoEnhancement>()).first?.copyedit, "Edited again on the phone.")
        // …but one inside the skew is the same moment, and the Mac's own write always lands.
        e.enhancedAt = (pf.syncedSourceEditedAt ?? t0).addingTimeInterval(ReconcileV2.Writers.skew - 1)
        try cloud.save()
        XCTAssertEqual(try ReconcileV2.Writers.upsertEnhancement(for: pf, into: cloud, deviceID: device), .written)
    }

    // MARK: - R57: diarization re-adopted when it changes, by content

    func testAPhoneReSplitReachesTheMacAndASteadySweepReadsNoBlob_R57() throws {
        let first = [DiarizedSegment(speaker: 0, start: 0, end: 4), DiarizedSegment(speaker: 1, start: 4, end: 9)]
        let memo = try voiceMemo(transcript: "**Ana:** The kiln.\n\n**Bo:** Loaded.", diarization: first)
        sweep()
        let pf = try XCTUnwrap(try row(memo.id))
        XCTAssertEqual(pf.diarizationSegments, first)

        // Re-split on the phone: new turns, same-length segments (a byte count would miss it).
        let second = [DiarizedSegment(speaker: 0, start: 0, end: 5), DiarizedSegment(speaker: 1, start: 5, end: 9)]
        memo.transcript = "**Ana:** The kiln is.\n\n**Bo:** Loaded."
        memo.markEdited()
        try setDiarization(memo, second)
        sweep()
        XCTAssertEqual(pf.diarizationSegments, second, "the re-split replaced the first segments")

        ReconcileWork.reset()
        XCTAssertEqual(sweep().updatedIDs, [])
        XCTAssertEqual(ReconcileWork.counts.assetBlobFetches, 0, "a steady sweep reads no diarization blob")
    }

    func testAMacMadeSplitIsNeverReplacedByAnUnchangedPhoneTranscript_R57() throws {
        let phone = [DiarizedSegment(speaker: 0, start: 0, end: 9)]
        let memo = try voiceMemo(transcript: "The kiln is loaded.", diarization: nil)
        sweep()
        let pf = try XCTUnwrap(try row(memo.id))
        let mac = [DiarizedSegment(speaker: 0, start: 0, end: 3), DiarizedSegment(speaker: 1, start: 3, end: 9)]
        pf.diarizationSegments = mac             // the Mac split it itself
        try setDiarization(memo, phone)           // a phone diarization lands later, words unchanged
        sweep()
        XCTAssertEqual(pf.diarizationSegments, mac)
    }

    // MARK: - C43 / C48

    func testAnAudioMemoWhoseBlobHasNotSyncedWaitsAndNeverBecomesText_C43() throws {
        let memo = Memo(id: UUID(), audioFilename: "memo_x.m4a", recordedAt: t0, transcript: "Words already.",
                        transcriptStatus: .done, transcriptConfidence: 0.9, significance: 0.5)
        cloud.insert(memo)
        try cloud.save()
        XCTAssertEqual(sweep().stranded, 1)
        XCTAssertNil(try row(memo.id), "no text row for a voice memo whose audio is on its way")
        cloud.insert(MemoAsset(memoID: memo.id, kind: MemoAsset.Kind.audio, filename: "memo_x.m4a", blob: Data("A".utf8)))
        try cloud.save()
        XCTAssertEqual(sweep().created, 1)
        XCTAssertEqual(try row(memo.id)?.sourceType, .audio)
    }

    func testSameIdClonesBecomeOneRow_C48() throws {
        let memo = try voiceMemo(transcript: "Kiln loaded.")
        let clone = Memo(id: memo.id, audioFilename: memo.audioFilename, recordedAt: t0, transcript: "Kiln loaded.",
                         transcriptStatus: .done, transcriptConfidence: 0.95, significance: 0.6)
        cloud.insert(clone)
        try cloud.save()
        sweep()
        XCTAssertEqual(try local.fetchCount(FetchDescriptor<PipelineFile>()), 1)
        XCTAssertEqual(sweep().updatedIDs, [], "the two never take turns rewriting the row")
    }

    // MARK: - C185 / C189

    func testNamesAndVocabularyReconcileBeforeTheMemos_C185() {
        let steps = ReconcileV2.Step.allCases
        XCTAssertEqual(Array(steps.prefix(4)), [.names, .vocabulary, .prompts, .sweep])
        XCTAssertLessThan(steps.firstIndex(of: .saveAndReexport)!, steps.firstIndex(of: .authorBackfill)!)
        XCTAssertLessThan(steps.firstIndex(of: .transcriptReflect)!, steps.firstIndex(of: .connectionsIndex)!)
    }

    func testOnlyNotesAlreadyInTheVaultReExport_C189() {
        func make(_ id: String, exported: Bool, locked: Bool = false, trashed: Bool = false) -> PipelineFile {
            let pf = PipelineFile(id: id, filename: id, sourceType: .audio)
            pf.exportStatus = exported ? .done : .pending
            pf.locked = locked
            pf.deletedAt = trashed ? t0 : nil
            return pf
        }
        let rows = [make("a", exported: true), make("b", exported: false), make("c", exported: true, locked: true),
                    make("d", exported: true, trashed: true)]
        XCTAssertEqual(ReconcileV2.reexportIDs(updated: ["a", "b", "c", "d", "a", "zz"], rows: rows), ["a"])
    }

    // MARK: - C186 / C188: writers

    func testWritersResolveThroughTheStoreAndNeverBumpTheEditTime_C186_C188() throws {
        let memo = Memo(id: UUID(), audioFilename: "memo_\(UUID().uuidString).m4a", recordedAt: t0, significance: 0.5,
                        createdAt: t0, editedAt: t0)
        cloud.insert(memo)
        try cloud.save()
        // A Mac recording: its filename carries the RECORDER's UUID, the row id is the memo's.
        let pf = PipelineFile(id: memo.id.uuidString, filename: memo.audioFilename, sourceType: .audio)
        pf.isLocalRecording = true
        XCTAssertEqual(ReconcileV2.Writers.resolve(pf, in: cloud)?.id, memo.id)

        let edited = memo.lastEditedAt
        XCTAssertTrue(ReconcileV2.Writers.setRating(nil, for: pf, in: cloud))
        XCTAssertEqual(memo.significance, 0, "clearing is an event that writes 0")
        XCTAssertFalse(ReconcileV2.Writers.setTitle("  ", for: pf, in: cloud), "no title yet: nothing to clear")
        XCTAssertTrue(ReconcileV2.Writers.setTitle("Kiln day", for: pf, in: cloud))
        XCTAssertTrue(ReconcileV2.Writers.setTitle("  ", for: pf, in: cloud))
        XCTAssertNil(memo.title, "blank clears the chosen title")
        pf.tags = ["glaze"]; pf.significance = 0.8
        XCTAssertTrue(ReconcileV2.Writers.mirrorMeta(pf, in: cloud))
        XCTAssertEqual(memo.tags, ["glaze"])
        pf.deletedAt = t0.addingTimeInterval(10)
        XCTAssertTrue(ReconcileV2.Writers.mirrorTrash(pf, in: cloud))
        XCTAssertEqual(memo.trashSeenAt, pf.deletedAt, "a Mac trash starts the purge clock at the same stamp")
        XCTAssertEqual(memo.lastEditedAt, edited, "no Mac -> phone meta write is a content edit")
    }

    // MARK: - C294: nothing to interleave with

    /// The sweep has no suspension point at all, so no query can observe a row mid-swap and no
    /// row is touched off its context's thread (the Q492 / Q505 / Q507 lesson).
    func testTheSweepHasNoAwait_C294() throws {
        let dir = CorpusSeed.fixtureRoot(file: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Skrift_Native/Shared/ReconcileV2")
        let files = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" }
        XCTAssertFalse(files.isEmpty)
        for file in files {
            let code = try String(contentsOf: file, encoding: .utf8).components(separatedBy: "\n")
                .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
                .joined(separator: "\n")
            XCTAssertFalse(code.contains("await "), "\(file.lastPathComponent) suspends")
            XCTAssertFalse(code.contains(" async "), "\(file.lastPathComponent) is async")
        }
    }
}
