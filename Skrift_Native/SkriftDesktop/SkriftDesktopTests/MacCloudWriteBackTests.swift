import XCTest
import SwiftData
import Foundation

/// 8c tests for the Mac→CloudKit WRITE-BACK (`MacCloudWriteBack`): the Mac's polish is
/// upserted as a `MemoEnhancement` keyed by the memo UUID, only for memos that actually
/// exist in the synced store, and only when there's something to sync.
@MainActor
final class MacCloudWriteBackTests: XCTestCase {

    /// An in-memory mirror of the CloudKit Memo store (Memo + MemoEnhancement + MemoAsset).
    private func cloudContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: Memo.self, MemoAsset.self, MemoEnhancement.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        return ModelContext(container)
    }

    private func enhancedFile(id: UUID, filename: String? = nil) -> PipelineFile {
        let pf = PipelineFile(id: id.uuidString, filename: filename ?? "memo_\(id.uuidString).m4a")
        pf.enhancedCopyedit = "Polished body."
        pf.enhancedTitle = "A good title"
        pf.enhancedSummary = "One-line summary."
        pf.enhanceStatus = .done
        return pf
    }

    private func enhancements(in ctx: ModelContext) -> [MemoEnhancement] {
        (try? ctx.fetch(FetchDescriptor<MemoEnhancement>())) ?? []
    }

    // MARK: - memoID recovery

    func testMemoIDFromMemoFilename() {
        let id = UUID()
        let pf = PipelineFile(id: "random-not-a-uuid", filename: "memo_\(id.uuidString).m4a")
        XCTAssertEqual(ReconcileV2.Writers.memoID(for: pf), id)
    }

    func testMemoIDFromCaptureFilename() {
        let id = UUID()
        let pf = PipelineFile(id: "random", filename: "capture_\(id.uuidString)")
        XCTAssertEqual(ReconcileV2.Writers.memoID(for: pf), id)
    }

    func testMemoIDFallsBackToRowID() {
        let id = UUID()
        // A locally-ingested file: filename carries no memo UUID, id is a plain UUID.
        let pf = PipelineFile(id: id.uuidString, filename: "some recording.m4a")
        XCTAssertEqual(ReconcileV2.Writers.memoID(for: pf), id)
    }

    // MARK: - Upsert

    func testUpsertWritesEnhancementForSyncedMemo() throws {
        let ctx = try cloudContext()
        let id = UUID()
        ctx.insert(Memo(id: id, audioFilename: "memo_\(id.uuidString).m4a"))
        try ctx.save()

        let written = try XCTUnwrap(
            try V2.upsert(enhancedFile(id: id), into: ctx, device: "mac-1"))
        XCTAssertEqual(written.memoID, id)
        XCTAssertEqual(written.copyedit, "Polished body.")
        XCTAssertEqual(written.title, "A good title")
        XCTAssertEqual(written.summary, "One-line summary.")
        XCTAssertEqual(written.enhancedByDeviceID, "mac-1")
        XCTAssertEqual(enhancements(in: ctx).count, 1)
    }

    func testUpsertIsIdempotentAndUpdatesInPlace() throws {
        let ctx = try cloudContext()
        let id = UUID()
        ctx.insert(Memo(id: id, audioFilename: "memo_\(id.uuidString).m4a"))
        try ctx.save()

        _ = try V2.upsert(enhancedFile(id: id), into: ctx, device: "mac-1")
        // A re-run (e.g. redo summary) with changed content must UPDATE, not duplicate.
        let pf = enhancedFile(id: id)
        pf.enhancedSummary = "Revised summary."
        // The same Mac: another device's unseen polish is refused instead (R44, `ReconcileV2Tests`).
        let written = try XCTUnwrap(try V2.upsert(pf, into: ctx, device: "mac-1"))
        XCTAssertEqual(enhancements(in: ctx).count, 1, "one enhancement per memo, updated in place")
        XCTAssertEqual(written.summary, "Revised summary.")
        XCTAssertEqual(written.enhancedByDeviceID, "mac-1")
    }

    func testNoWriteBackWhenMemoNotSynced() throws {
        let ctx = try cloudContext()
        // No Memo inserted — the file is local-only / not synced.
        let result = try V2.upsert(enhancedFile(id: UUID()), into: ctx, device: "mac-1")
        XCTAssertNil(result, "never orphan an enhancement onto a non-synced memo")
        XCTAssertEqual(enhancements(in: ctx).count, 0)
    }

    func testNoWriteBackWhenNothingEnhanced() throws {
        let ctx = try cloudContext()
        let id = UUID()
        ctx.insert(Memo(id: id, audioFilename: "memo_\(id.uuidString).m4a"))
        try ctx.save()

        let pf = PipelineFile(id: id.uuidString, filename: "memo_\(id.uuidString).m4a")  // no enhanced* fields
        XCTAssertNil(try V2.upsert(pf, into: ctx, device: "mac-1"))
        XCTAssertEqual(enhancements(in: ctx).count, 0)
    }

    // MARK: - A pass that produced nothing is still a pass (2026-08-26)

    /// The bug this closes: a note the model had nothing to say about (a bare shared photo,
    /// three words, a link with no comment) wrote NO enhancement row, so the phone and iPad
    /// could never learn it had been processed — the export button said "Process this note
    /// first" forever and pressing it did the identical nothing.
    func testPassWithEmptyResultRecordsTheRunWithoutContent() throws {
        let ctx = try cloudContext()
        let id = UUID()
        ctx.insert(Memo(id: id, audioFilename: "memo_\(id.uuidString).m4a"))
        try ctx.save()

        let pf = PipelineFile(id: id.uuidString, filename: "memo_\(id.uuidString).m4a")
        pf.enhanceStatus = .done                    // BatchRunner marks an empty input done
        let written = try XCTUnwrap(
            try V2.upsert(pf, into: ctx, device: "mac-1", passRan: true))

        XCTAssertEqual(enhancements(in: ctx).count, 1, "the run is a fact worth syncing")
        XCTAssertFalse(written.hasContent, "…and it genuinely produced nothing")
        XCTAssertNotNil(written.processedAt)
        XCTAssertTrue(written.isProcessed, "so every gate must read it as processed")
    }

    /// The other half: a MANUAL edit re-sync is not a pass. Without this split, every
    /// empty edit write-back would mint a placeholder row.
    func testEditResyncNeverRecordsARun() throws {
        let ctx = try cloudContext()
        let id = UUID()
        ctx.insert(Memo(id: id, audioFilename: "memo_\(id.uuidString).m4a"))
        try ctx.save()

        let written = try XCTUnwrap(
            try V2.upsert(enhancedFile(id: id), into: ctx, device: "mac-1", body: "Hand-edited body."))
        XCTAssertNil(written.processedAt, "an edit is not a model pass")
        XCTAssertTrue(written.isProcessed, "…but the content it carries still proves one ran")
    }

    /// Rows written before `processedAt` existed carry nil, so `isProcessed` falls back to
    /// ALL THREE parts — never "any part", because a note's polished title is also written
    /// from the user's own chosen title.
    func testLegacyRowsFallBackToAllThreeParts() {
        let full = MemoEnhancement(memoID: UUID(), copyedit: "Body.", title: "T", summary: "S")
        XCTAssertTrue(full.isProcessed)

        let retitledOnly = MemoEnhancement(memoID: UUID(), title: "A title I typed")
        XCTAssertTrue(retitledOnly.hasContent, "hasContent is any-part, by design")
        XCTAssertFalse(retitledOnly.isProcessed, "a merely retitled note was never processed")
    }

    // MARK: - Part B: live-edit write-back (bodyOverride + echo guard)

    func testBodyOverrideSyncsTheEditedBodyNotStaleCopyedit() throws {
        // A manual Mac body edit lands in `sanitised`; the edit path passes the un-linked
        // body via bodyOverride, which must win over the stale `enhancedCopyedit`.
        let ctx = try cloudContext()
        let id = UUID()
        ctx.insert(Memo(id: id, audioFilename: "memo_\(id.uuidString).m4a"))
        try ctx.save()

        let pf = enhancedFile(id: id)   // enhancedCopyedit = "Polished body."
        let written = try XCTUnwrap(try V2.upsert(pf, into: ctx, device: "mac-1", body: "Edited on the Mac."))
        XCTAssertEqual(written.copyedit, "Edited on the Mac.", "bodyOverride is the live-edited body")
    }

    func testUpsertDoesNotClobberANewerPhoneEdit() throws {
        // A phone edit (device "phone-9") landed at a LATER time than this Mac write's `now`.
        // LWW must preserve the phone's copy, not overwrite it with the Mac's stale content.
        let ctx = try cloudContext()
        let id = UUID()
        ctx.insert(Memo(id: id, audioFilename: "memo_\(id.uuidString).m4a"))
        let future = Date().addingTimeInterval(60)
        let phoneEdit = MemoEnhancement(memoID: id, copyedit: "Phone's newer text.",
                                        enhancedByDeviceID: "phone-9", enhancedAt: future)
        ctx.insert(phoneEdit)
        try ctx.save()

        let result = try V2.upsert(enhancedFile(id: id), into: ctx, device: "mac-1", now: Date())
        XCTAssertEqual(result?.copyedit, "Phone's newer text.", "a strictly-newer phone edit is preserved")
        XCTAssertEqual(enhancements(in: ctx).count, 1)
    }

    func testUpsertOverwritesItsOwnEarlierWrite() throws {
        // The guard is only against OTHER devices — the Mac freely updates its own prior write.
        let ctx = try cloudContext()
        let id = UUID()
        ctx.insert(Memo(id: id, audioFilename: "memo_\(id.uuidString).m4a"))
        ctx.insert(MemoEnhancement(memoID: id, copyedit: "Old.",
                                   enhancedByDeviceID: "mac-1", enhancedAt: Date().addingTimeInterval(60)))
        try ctx.save()

        let written = try XCTUnwrap(try V2.upsert(enhancedFile(id: id), into: ctx, device: "mac-1", body: "New from the same Mac."))
        XCTAssertEqual(written.copyedit, "New from the same Mac.")
    }

    func testCaptureWriteBackUsesTitleAndSummaryOnly() throws {
        // Captures get title + summary but no copy-edit (BatchRunner.runCapture) — still synced.
        let ctx = try cloudContext()
        let id = UUID()
        ctx.insert(Memo(id: id, audioFilename: ""))
        try ctx.save()

        let pf = PipelineFile(id: id.uuidString, filename: "capture_\(id.uuidString)", sourceType: .capture)
        pf.enhancedTitle = "Saved link"
        pf.enhancedSummary = "Why it matters."
        pf.enhanceStatus = .done
        let written = try XCTUnwrap(try V2.upsert(pf, into: ctx, device: "mac-1"))
        XCTAssertEqual(written.title, "Saved link")
        XCTAssertEqual(written.summary, "Why it matters.")
        XCTAssertEqual(written.copyedit, "")
        XCTAssertTrue(written.hasContent)
    }
}
