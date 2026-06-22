import XCTest
import SwiftData
import Foundation

/// 8c tests for the Mac→CloudKit WRITE-BACK (`MacCloudWriteBack`): the Mac's polish is
/// upserted as a `MemoEnhancement` keyed by the memo UUID, only for memos that actually
/// exist in the synced store, and only when there's something to sync.
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
        XCTAssertEqual(MacCloudWriteBack.memoID(for: pf), id)
    }

    func testMemoIDFromCaptureFilename() {
        let id = UUID()
        let pf = PipelineFile(id: "random", filename: "capture_\(id.uuidString)")
        XCTAssertEqual(MacCloudWriteBack.memoID(for: pf), id)
    }

    func testMemoIDFallsBackToRowID() {
        let id = UUID()
        // A locally-ingested file: filename carries no memo UUID, id is a plain UUID.
        let pf = PipelineFile(id: id.uuidString, filename: "some recording.m4a")
        XCTAssertEqual(MacCloudWriteBack.memoID(for: pf), id)
    }

    // MARK: - Upsert

    func testUpsertWritesEnhancementForSyncedMemo() throws {
        let ctx = try cloudContext()
        let id = UUID()
        ctx.insert(Memo(id: id, audioFilename: "memo_\(id.uuidString).m4a"))
        try ctx.save()

        let written = try XCTUnwrap(
            try MacCloudWriteBack.upsert(for: enhancedFile(id: id), into: ctx, deviceID: "mac-1"))
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

        _ = try MacCloudWriteBack.upsert(for: enhancedFile(id: id), into: ctx, deviceID: "mac-1")
        // A re-run (e.g. redo summary) with changed content must UPDATE, not duplicate.
        let pf = enhancedFile(id: id)
        pf.enhancedSummary = "Revised summary."
        let written = try XCTUnwrap(try MacCloudWriteBack.upsert(for: pf, into: ctx, deviceID: "mac-2"))
        XCTAssertEqual(enhancements(in: ctx).count, 1, "one enhancement per memo, updated in place")
        XCTAssertEqual(written.summary, "Revised summary.")
        XCTAssertEqual(written.enhancedByDeviceID, "mac-2")
    }

    func testNoWriteBackWhenMemoNotSynced() throws {
        let ctx = try cloudContext()
        // No Memo inserted — the file is local-only / not synced.
        let result = try MacCloudWriteBack.upsert(for: enhancedFile(id: UUID()), into: ctx, deviceID: "mac-1")
        XCTAssertNil(result, "never orphan an enhancement onto a non-synced memo")
        XCTAssertEqual(enhancements(in: ctx).count, 0)
    }

    func testNoWriteBackWhenNothingEnhanced() throws {
        let ctx = try cloudContext()
        let id = UUID()
        ctx.insert(Memo(id: id, audioFilename: "memo_\(id.uuidString).m4a"))
        try ctx.save()

        let pf = PipelineFile(id: id.uuidString, filename: "memo_\(id.uuidString).m4a")  // no enhanced* fields
        XCTAssertNil(try MacCloudWriteBack.upsert(for: pf, into: ctx, deviceID: "mac-1"))
        XCTAssertEqual(enhancements(in: ctx).count, 0)
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
        let written = try XCTUnwrap(try MacCloudWriteBack.upsert(for: pf, into: ctx, deviceID: "mac-1"))
        XCTAssertEqual(written.title, "Saved link")
        XCTAssertEqual(written.summary, "Why it matters.")
        XCTAssertEqual(written.copyedit, "")
        XCTAssertTrue(written.hasContent)
    }
}
