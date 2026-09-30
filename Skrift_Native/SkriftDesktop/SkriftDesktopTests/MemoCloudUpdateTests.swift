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

    // MARK: - Destination (2026-08-26)

    /// The destination travels phone→Mac, because the Mac is the device that actually
    /// writes the portfolio folder. Picking "Idea" on the phone and having the Mac still
    /// think "Personal" would send a note to the wrong side of a PRIVACY boundary.
    func testDestinationIsReflectedFromThePhone() {
        let id = UUID()
        let t0 = Date()
        let pf = ingestedFile(id: id, at: t0)
        XCTAssertEqual(pf.destination, .personal, "the default, i.e. today's behaviour")

        let m = memo(id, transcript: "Original transcript.", editedAt: t0.addingTimeInterval(10))
        m.destination = .idea

        XCTAssertTrue(MemoCloudUpdate.apply(memo: m, enhancement: nil, to: pf,
                                            people: [], author: "Me", thisDeviceID: mac))
        XCTAssertEqual(pf.destination, .idea)
    }

    /// One-of-four all the way through: a later change REPLACES, never accumulates.
    func testDestinationChangeReplacesTheLastOne() {
        let id = UUID()
        let t0 = Date()
        let pf = ingestedFile(id: id, at: t0)
        pf.destination = .inspiration

        let m = memo(id, transcript: "Original transcript.", editedAt: t0.addingTimeInterval(10))
        m.destination = .project

        _ = MemoCloudUpdate.apply(memo: m, enhancement: nil, to: pf,
                                  people: [], author: "Me", thisDeviceID: mac)
        XCTAssertEqual(pf.destination, .project)
    }

    /// An unreadable value degrades to the PRIVATE side on both models — never guessed
    /// as one that leaves.
    func testUnknownDestinationDegradesToPersonalOnThePipelineFile() {
        let pf = ingestedFile(id: UUID(), at: Date())
        pf.destinationRaw = "something-a-future-build-wrote"
        XCTAssertEqual(pf.destination, .personal)
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

    func testTrashedMemoMirrorsTrashButSkipsTextRecompile() {
        let id = UUID()
        let t0 = Date()
        let pf = ingestedFile(id: id, at: t0)   // active, transcript "Original transcript.", never compiled
        let m = memo(id, transcript: "Edited then deleted.", editedAt: t0.addingTimeInterval(10))
        let trashedAt = Date()
        m.deletedAt = trashedAt

        // The trash state DOES mirror onto the row (delete-sync)…
        XCTAssertTrue(MemoCloudUpdate.apply(memo: m, enhancement: nil, to: pf,
                                            people: [], author: "", thisDeviceID: mac))
        XCTAssertEqual(pf.deletedAt, trashedAt)
        // …but the pending text edit is NOT reflected and nothing recompiles — it's in the bin.
        XCTAssertEqual(pf.transcript, "Original transcript.", "a trashed memo's text edit is not reflected")
        XCTAssertNil(pf.sanitised, "no recompile for a trashed memo")
    }

    // MARK: - Row mirrors (lock / reminder / photo OCR) — no recompile needed

    /// Baseline a row whose blob already matches the memo's (as a real ingest leaves it),
    /// so mirror tests isolate the mirror change from a blob refresh.
    private func baselined(_ pf: PipelineFile, to m: Memo) -> PipelineFile {
        pf.audioMetadataJSON = MemoCloudIngest.metadataJSON(for: m)
        pf.transcript = m.transcript
        pf.tags = m.tags                 // as MemoCloudIngest now leaves them
        pf.significance = m.significance
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

    // MARK: - Tags + importance reflect (widen the Mac→phone channel; phone→Mac side)

    func testPhoneTagEditIsReflectedOntoTheRow() {
        let id = UUID()
        let t0 = Date()
        let m = memo(id, transcript: "Original transcript.", editedAt: t0)
        let pf = baselined(ingestedFile(id: id, at: t0), to: m)   // tags match at baseline ([])
        m.tags = ["work", "ideas"]
        m.markEdited(t0.addingTimeInterval(10))

        XCTAssertTrue(MemoCloudUpdate.apply(memo: m, enhancement: nil, to: pf,
                                            people: [], author: "", thisDeviceID: mac))
        XCTAssertEqual(pf.tags, ["work", "ideas"], "a phone tag edit reflects onto the Mac row")
    }

    func testPhoneImportanceEditIsReflected() throws {
        let id = UUID()
        let t0 = Date()
        let m = memo(id, transcript: "Original transcript.", editedAt: t0)   // significance 0.6
        let pf = baselined(ingestedFile(id: id, at: t0), to: m)
        m.significance = 0.9
        m.markEdited(t0.addingTimeInterval(10))

        XCTAssertTrue(MemoCloudUpdate.apply(memo: m, enhancement: nil, to: pf,
                                            people: [], author: "", thisDeviceID: mac))
        XCTAssertEqual(try XCTUnwrap(pf.significance), 0.9, accuracy: 0.0001, "a phone importance edit reflects")
    }

    // MARK: - Delete sync (trash + restore mirror, both ways)

    func testPhoneTrashIsMirroredOntoTheRow() {
        let id = UUID()
        let t0 = Date()
        let m = memo(id, transcript: "Original transcript.", editedAt: t0)
        let pf = baselined(ingestedFile(id: id, at: t0), to: m)   // active on the Mac, watermark nil
        let trashedAt = t0.addingTimeInterval(30)
        m.deletedAt = trashedAt                                    // the phone binned it

        XCTAssertTrue(MemoCloudUpdate.apply(memo: m, enhancement: nil, to: pf,
                                            people: [], author: "", thisDeviceID: mac))
        XCTAssertEqual(pf.deletedAt, trashedAt, "the phone trash mirrors onto the Mac row")
        XCTAssertEqual(pf.syncedSourceDeletedAt, trashedAt, "reflect watermark advanced")
    }

    func testPhoneRestoreIsMirrored() {
        let id = UUID()
        let t0 = Date()
        let trashedAt = t0.addingTimeInterval(30)
        let m = memo(id, transcript: "Original transcript.", editedAt: t0)   // active (deletedAt nil)
        let pf = baselined(ingestedFile(id: id, at: t0), to: m)
        pf.deletedAt = trashedAt                 // the Mac has it trashed…
        pf.syncedSourceDeletedAt = trashedAt     // …reflected from an earlier phone trash

        XCTAssertTrue(MemoCloudUpdate.apply(memo: m, enhancement: nil, to: pf,
                                            people: [], author: "", thisDeviceID: mac))
        XCTAssertNil(pf.deletedAt, "the phone restore clears the Mac row's trash")
        XCTAssertNil(pf.syncedSourceDeletedAt)
    }

    func testMacLocalTrashIsNotClobberedByAnActiveMemo() {
        let id = UUID()
        let t0 = Date()
        let m = memo(id, transcript: "Original transcript.", editedAt: t0)   // active, unchanged
        let pf = baselined(ingestedFile(id: id, at: t0), to: m)
        let macTrashedAt = t0.addingTimeInterval(30)
        pf.deletedAt = macTrashedAt              // trashed ONLY on the Mac (pre-delete-sync)…
        pf.syncedSourceDeletedAt = nil           // …never reflected from the phone

        XCTAssertFalse(MemoCloudUpdate.apply(memo: m, enhancement: nil, to: pf,
                                             people: [], author: "", thisDeviceID: mac),
                       "an active memo whose deletedAt didn't change must not touch the row")
        XCTAssertEqual(pf.deletedAt, macTrashedAt, "the Mac-local trash survives the sweep")
    }

    func testTrashReflectIsIdempotent() {
        let id = UUID()
        let t0 = Date()
        let trashedAt = t0.addingTimeInterval(30)
        let m = memo(id, transcript: "Original transcript.", editedAt: t0)
        m.deletedAt = trashedAt
        let pf = baselined(ingestedFile(id: id, at: t0), to: m)
        pf.deletedAt = trashedAt
        pf.syncedSourceDeletedAt = trashedAt     // already reflected

        XCTAssertFalse(MemoCloudUpdate.apply(memo: m, enhancement: nil, to: pf,
                                             people: [], author: "", thisDeviceID: mac),
                       "same trash state → no work, no loop")
    }

    // MARK: - Path 2b: the title chosen on another device (2026-07-27)

    /// A title picked on the phone/iPad writes `Memo.title` — the field every device's list
    /// renders. The Mac must adopt it, not just its own `enhancement.title` suggestion.
    func testTitleChosenOnAnotherDeviceIsAdopted() {
        let id = UUID(), t0 = Date()
        let pf = ingestedFile(id: id, at: t0)
        pf.enhancedTitle = "Mac's own suggestion"
        let m = memo(id, transcript: "Original transcript.", editedAt: t0.addingTimeInterval(10))
        m.title = "The one Tuur picked"

        XCTAssertTrue(MemoCloudUpdate.apply(memo: m, enhancement: nil, to: pf,
                                            people: [], author: "Me", thisDeviceID: mac))
        XCTAssertEqual(pf.enhancedTitle, "The one Tuur picked")
    }

    /// Idempotent: once the title agrees, later sweeps must report NO change — otherwise
    /// this row churns and re-exports on every pass, forever (the `reflected=N` symptom).
    /// Asserted as a settle: the first apply may legitimately do other work (metadata
    /// baseline), the SECOND must be silent.
    func testAgreeingTitleDoesNotChurnLaterSweeps() {
        let id = UUID(), t0 = Date()
        let pf = ingestedFile(id: id, at: t0)
        let m = memo(id, transcript: "Original transcript.", editedAt: t0)
        m.title = "Same title"

        _ = MemoCloudUpdate.apply(memo: m, enhancement: nil, to: pf,
                                  people: [], author: "Me", thisDeviceID: mac)
        XCTAssertEqual(pf.enhancedTitle, "Same title")

        XCTAssertFalse(MemoCloudUpdate.apply(memo: m, enhancement: nil, to: pf,
                                             people: [], author: "Me", thisDeviceID: mac),
                       "settled title → no work on the next sweep")
    }

    /// REGRESSION GUARD: a nil/blank `Memo.title` must NOT wipe the Mac's own generated
    /// suggestion. nil is the DEFAULT state of every note nobody has chosen a title for,
    /// and a generated suggestion lives only on the row (`pf.enhancedTitle`) — it never
    /// writes `Memo.title`. An earlier draft of path 2b cleared on nil, which erased every
    /// Mac-generated title on the next sweep.
    func testBlankPhoneTitleNeverWipesTheMacSuggestion() {
        let id = UUID(), t0 = Date()
        let pf = ingestedFile(id: id, at: t0)
        pf.enhancedTitle = "Mac's generated suggestion"
        let m = memo(id, transcript: "Original transcript.", editedAt: t0.addingTimeInterval(10))
        m.title = "   "   // i.e. nobody has chosen a title

        _ = MemoCloudUpdate.apply(memo: m, enhancement: nil, to: pf,
                                  people: [], author: "Me", thisDeviceID: mac)
        XCTAssertEqual(pf.enhancedTitle, "Mac's generated suggestion", "adopt-only, never clear")
    }
}
