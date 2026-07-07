import XCTest
import Foundation

/// Part B (phone→Mac live sync) tests for `MemoCloudUpdate.apply`: reflect a NEWER phone edit
/// to an already-ingested memo into its `PipelineFile` — re-link + recompile, no LLM — while the
/// echo guard ignores the Mac's own write-back and the watermark makes each edit reflect once.
final class MemoCloudUpdateTests: XCTestCase {

    private let mac = "mac-1"

    private func ingestedFile(id: UUID, at baseline: Date) -> PipelineFile {
        let pf = PipelineFile(id: id.uuidString, filename: "memo_\(id.uuidString).m4a")
        pf.transcript = "Original transcript."
        pf.transcribeStatus = .done
        pf.syncedSourceEditedAt = baseline   // what MemoCloudIngest baselines to memo.lastEditedAt
        return pf
    }

    private func memo(_ id: UUID, transcript: String, editedAt: Date) -> Memo {
        let m = Memo(id: id, audioFilename: "memo_\(id.uuidString).m4a", recordedAt: Date(),
                     transcript: transcript, transcriptStatus: .done, transcriptConfidence: 0.9,
                     significance: 0.6)
        m.markEdited(editedAt)
        return m
    }

    // MARK: - Path 3: raw transcript edit

    func testRawTranscriptEditIsReflectedAndReSanitised() {
        let id = UUID()
        let t0 = Date()
        let pf = ingestedFile(id: id, at: t0)
        let m = memo(id, transcript: "Edited on the phone.", editedAt: t0.addingTimeInterval(10))

        let changed = MemoCloudUpdate.apply(memo: m, enhancement: nil, to: pf,
                                            people: [], author: "Me", thisDeviceID: mac)
        XCTAssertTrue(changed)
        XCTAssertEqual(pf.transcript, "Edited on the phone.")
        XCTAssertEqual(pf.sanitised, "Edited on the phone.", "re-sanitised (no people → unchanged text)")
        XCTAssertEqual(pf.sanitiseStatus, .done)
        XCTAssertNotNil(pf.compiledText)
        XCTAssertEqual(pf.syncedSourceEditedAt, m.lastEditedAt, "watermark advanced past the edit")
    }

    func testSecondApplyIsANoOpUntilANewerEdit() {
        let id = UUID()
        let t0 = Date()
        let pf = ingestedFile(id: id, at: t0)
        let m = memo(id, transcript: "First edit.", editedAt: t0.addingTimeInterval(10))

        XCTAssertTrue(MemoCloudUpdate.apply(memo: m, enhancement: nil, to: pf,
                                            people: [], author: "", thisDeviceID: mac))
        // Same edit time → nothing newer → no work (idempotent, never loops).
        XCTAssertFalse(MemoCloudUpdate.apply(memo: m, enhancement: nil, to: pf,
                                             people: [], author: "", thisDeviceID: mac))
    }

    // MARK: - Path 2: polished copy-edit edit (phone-authored enhancement)

    func testPhoneCopyeditEditIsAdopted() {
        let id = UUID()
        let t0 = Date()
        let pf = ingestedFile(id: id, at: t0)
        pf.enhancedCopyedit = "Old copy-edit."
        pf.enhanceStatus = .done
        let m = memo(id, transcript: "Original transcript.", editedAt: t0.addingTimeInterval(5))
        let enh = MemoEnhancement(memoID: id, copyedit: "Phone-edited copy-edit.",
                                  enhancedByDeviceID: "phone-9", enhancedAt: t0.addingTimeInterval(10))

        let changed = MemoCloudUpdate.apply(memo: m, enhancement: enh, to: pf,
                                            people: [], author: "", thisDeviceID: mac)
        XCTAssertTrue(changed)
        XCTAssertEqual(pf.enhancedCopyedit, "Phone-edited copy-edit.")
        XCTAssertEqual(pf.sanitised, "Phone-edited copy-edit.")
    }

    func testPolishedEditAppliesEvenWhenMemoEditedAfterEnhancement() {
        // Regression (device-found): the phone stamps enhancement.enhancedAt, THEN memo.markEdited()
        // — so memo.lastEditedAt > enhancement.enhancedAt for the SAME copy-edit. A timestamp-gated
        // path selection dropped it; content-based must apply it, even with a poisoned watermark.
        let id = UUID()
        let t0 = Date()
        let pf = ingestedFile(id: id, at: t0)
        pf.enhancedCopyedit = "Mac copy-edit."
        pf.enhanceStatus = .done
        pf.syncedSourceEditedAt = t0.addingTimeInterval(20)   // a prior buggy run already advanced it
        let m = memo(id, transcript: "Original transcript.", editedAt: t0.addingTimeInterval(11))
        let enh = MemoEnhancement(memoID: id, copyedit: "Phone-edited copy-edit.",
                                  enhancedByDeviceID: "phone-9", enhancedAt: t0.addingTimeInterval(10))

        let changed = MemoCloudUpdate.apply(memo: m, enhancement: enh, to: pf,
                                            people: [], author: "", thisDeviceID: mac)
        XCTAssertTrue(changed, "a differing phone copy-edit is applied regardless of timestamps/watermark")
        XCTAssertEqual(pf.enhancedCopyedit, "Phone-edited copy-edit.")
        XCTAssertEqual(pf.sanitised, "Phone-edited copy-edit.")
    }

    // MARK: - Echo guard + no-op

    func testMacOwnWriteBackIsNotEchoed() {
        // The Mac's own enhancement (its deviceID) syncs back via CloudKit; it must be ignored,
        // and with no newer memo edit there's nothing to reflect.
        let id = UUID()
        let t0 = Date()
        let m = memo(id, transcript: "Original transcript.", editedAt: t0)   // memo NOT re-edited
        let pf = baselined(ingestedFile(id: id, at: t0), to: m)   // as a real ingest leaves it
        pf.enhancedCopyedit = "Mac copy-edit."
        let ownEnh = MemoEnhancement(memoID: id, copyedit: "Mac's own write-back.",
                                     enhancedByDeviceID: mac, enhancedAt: t0.addingTimeInterval(30))

        let changed = MemoCloudUpdate.apply(memo: m, enhancement: ownEnh, to: pf,
                                            people: [], author: "", thisDeviceID: mac)
        XCTAssertFalse(changed, "the Mac never re-reflects its own write-back")
        XCTAssertEqual(pf.enhancedCopyedit, "Mac copy-edit.", "untouched")
    }

    func testNoOpWhenNothingNewer() {
        let id = UUID()
        let t0 = Date()
        let m = memo(id, transcript: "Original transcript.", editedAt: t0)   // == baseline
        let pf = baselined(ingestedFile(id: id, at: t0), to: m)   // as a real ingest leaves it
        XCTAssertFalse(MemoCloudUpdate.apply(memo: m, enhancement: nil, to: pf,
                                             people: [], author: "", thisDeviceID: mac))
    }

    func testTrashedMemoIsNotReflected() {
        let id = UUID()
        let t0 = Date()
        let pf = ingestedFile(id: id, at: t0)
        let m = memo(id, transcript: "Edited then deleted.", editedAt: t0.addingTimeInterval(10))
        m.deletedAt = Date()
        XCTAssertFalse(MemoCloudUpdate.apply(memo: m, enhancement: nil, to: pf,
                                             people: [], author: "", thisDeviceID: mac))
    }

    // MARK: - Row mirrors (lock / reminder / photo OCR) — no recompile needed

    /// Baseline a row whose blob already matches the memo's (as a real ingest leaves it),
    /// so mirror tests isolate the mirror change from a blob refresh.
    private func baselined(_ pf: PipelineFile, to m: Memo) -> PipelineFile {
        pf.audioMetadataJSON = MemoCloudIngest.metadataJSON(for: m)
        pf.transcript = m.transcript
        return pf
    }

    func testLockToggleMirrorsWithoutRecompile() {
        let id = UUID()
        let t0 = Date()
        let m = memo(id, transcript: "Original transcript.", editedAt: t0)
        let pf = baselined(ingestedFile(id: id, at: m.lastEditedAt), to: m)
        pf.compiledText = "COMPILED-BEFORE"

        m.locked = true
        XCTAssertTrue(MemoCloudUpdate.apply(memo: m, enhancement: nil, to: pf,
                                            people: [], author: "", thisDeviceID: mac))
        XCTAssertTrue(pf.locked, "lock flag mirrored")
        XCTAssertEqual(pf.compiledText, "COMPILED-BEFORE", "meta-only change must not recompile")

        // Unlock mirrors back too (and the wiring re-exports on the same sweep).
        m.locked = false
        XCTAssertTrue(MemoCloudUpdate.apply(memo: m, enhancement: nil, to: pf,
                                            people: [], author: "", thisDeviceID: mac))
        XCTAssertFalse(pf.locked)
    }

    func testReminderMirrors() {
        let id = UUID()
        let m = memo(id, transcript: "Original transcript.", editedAt: Date())
        let pf = baselined(ingestedFile(id: id, at: m.lastEditedAt), to: m)

        let remind = Date().addingTimeInterval(3600)
        m.remindAt = remind
        XCTAssertTrue(MemoCloudUpdate.apply(memo: m, enhancement: nil, to: pf,
                                            people: [], author: "", thisDeviceID: mac))
        XCTAssertEqual(pf.remindAt, remind)
    }

    /// Photo OCR lands AFTER the first sync (the phone indexes in the background) — the
    /// updated manifest must reach the Mac row: flat search text + refreshed blob.
    func testLateOCRTextReachesTheRow() {
        let id = UUID()
        let m = memo(id, transcript: "Original transcript.", editedAt: Date())
        let pf = baselined(ingestedFile(id: id, at: m.lastEditedAt), to: m)

        m.metadata = MemoMetadata(imageManifest: [
            ImageManifestEntry(filename: "img_001.jpg", offsetSeconds: 1, text: "WHITEBOARD ROADMAP"),
        ])
        XCTAssertTrue(MemoCloudUpdate.apply(memo: m, enhancement: nil, to: pf,
                                            people: [], author: "", thisDeviceID: mac))
        XCTAssertEqual(pf.imageOCRText, "WHITEBOARD ROADMAP")
        XCTAssertEqual(pf.audioMetadataJSON, MemoCloudIngest.metadataJSON(for: m),
                       "stored blob refreshed to the new manifest")
    }
}
