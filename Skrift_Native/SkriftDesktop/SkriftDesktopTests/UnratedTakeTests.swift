import XCTest

/// The unrated-take doctrine (2026-07-28, `LANES-2026-07-28/BRIEF_DOCTRINE.md`): an
/// unrated Mac take must behave like an unrated phone memo — no lit queue row, not
/// counted into "Process N", refused by `needsProcessing`. Pure logic, no
/// `ModelContext` — the MLX-free `UnitTests` scheme. Sibling of the ② band-membership
/// suite in `WayOutRulesTests.swift` (same target); this file is the focused pin for
/// the three new `WayOutRules` predicates (`isUnratedLocalRecording`,
/// `isQuietLocalTake`, `needsProcessing`) the doctrine introduced.
final class UnratedTakeTests: XCTestCase {

    private func file(isLocalRecording: Bool = false, significance: Double? = nil,
                      error: String? = nil, transcribeStatus: StepStatus = .done,
                      enhanceStatus: StepStatus = .pending, deletedAt: Date? = nil) -> PipelineFile {
        let pf = PipelineFile(id: UUID().uuidString, filename: "x.m4a", sourceType: .audio, uploadedAt: Date())
        pf.isLocalRecording = isLocalRecording
        pf.significance = significance
        pf.error = error
        pf.transcribeStatus = transcribeStatus
        pf.enhanceStatus = enhanceStatus
        pf.deletedAt = deletedAt
        return pf
    }

    private func memo(id: UUID, significance: Double = 0) -> Memo {
        Memo(id: id, audioFilename: "memo_\(id.uuidString).m4a", recordedAt: Date(),
             transcript: "hello", transcriptStatus: .done, significance: significance)
    }

    // MARK: - 1. An unrated, error-free local recording

    func testUnratedErrorFreeLocalRecordingIsAQuietLocalTake() {
        let pf = file(isLocalRecording: true)
        XCTAssertTrue(WayOutRules.isQuietLocalTake(pf))
    }

    func testUnratedErrorFreeLocalRecordingRefusesProcessing() {
        let pf = file(isLocalRecording: true)
        XCTAssertFalse(WayOutRules.needsProcessing(pf))
    }

    func testUnratedLocalRecordingsTwinMemoSurfacesInTheQuietList() {
        // Its pipeline row still exists (it holds the transcript) — only the
        // ROW-VISIBILITY channel changes: the row stops being lit, and the twin
        // memo takes its place in the quiet list, same id.
        let id = UUID()
        let m = memo(id: id)
        let pf = file(isLocalRecording: true)
        pf.id = id.uuidString
        XCTAssertEqual(WayOutRules.unpipelined(memos: [m], files: [pf]).map(\.id), [id])
    }

    // MARK: - 2. A rated local recording passes

    func testRatedLocalRecordingNeedsProcessing() {
        let pf = file(isLocalRecording: true, significance: 0.3)
        XCTAssertTrue(WayOutRules.needsProcessing(pf))
        XCTAssertFalse(WayOutRules.isQuietLocalTake(pf))
    }

    func testRatedLocalRecordingsTwinMemoIsNotInTheQuietList() {
        let id = UUID()
        // The memo's own significance is what a real rating write (`MacCloudMetaSync
        // .setRating`) mirrors onto too — but the row-membership check only needs
        // `pf.significance` to have flipped; assert against that alone here.
        let m = memo(id: id, significance: 0)
        let pf = file(isLocalRecording: true, significance: 0.3)
        pf.id = id.uuidString
        XCTAssertTrue(WayOutRules.unpipelined(memos: [m], files: [pf]).isEmpty)
    }

    // MARK: - 3. An unrated import is unaffected (never isLocalRecording)

    func testUnratedImportFlooredToRatedIsUnaffected() {
        // Imports floor to rated via the memo channel (`MacMemoAuthor`'s 0.1 floor):
        // isLocalRecording stays false, so neither predicate engages regardless of
        // the significance value.
        let pf = file(isLocalRecording: false, significance: 0.1)
        XCTAssertTrue(WayOutRules.needsProcessing(pf))
        XCTAssertFalse(WayOutRules.isQuietLocalTake(pf))
    }

    func testUnratedNonLocalFileNeedsProcessingRegardlessOfSignificance() {
        // A plain unrated (significance nil) non-local row — e.g. a legacy
        // pre-`isLocalRecording`-flag take — must NOT be swept up by the doctrine;
        // it behaves exactly as `needsProcessing` did before this lane's change.
        let pf = file(isLocalRecording: false, significance: nil)
        XCTAssertTrue(WayOutRules.needsProcessing(pf))
        XCTAssertFalse(WayOutRules.isQuietLocalTake(pf))
    }

    // MARK: - 4. The errored unrated take: queue member, gate still shut

    func testErroredUnratedLocalTakeIsNotAQuietLocalTake() {
        // Errors stay loud: it keeps its queue row (and Error chip via the
        // existing `queueStatus`), so it must not ALSO be routed to the quiet
        // channel — a failed capture that quietly faded would bury a real failure.
        let pf = file(isLocalRecording: true, error: "boom", transcribeStatus: .error)
        XCTAssertFalse(WayOutRules.isQuietLocalTake(pf))
    }

    func testErroredUnratedLocalTakeStillRefusesProcessing() {
        // Only explicit per-row verbs (Re-transcribe) may act on it — the Process
        // gate stays shut even though the row is visible.
        let pf = file(isLocalRecording: true, error: "boom", transcribeStatus: .error)
        XCTAssertFalse(WayOutRules.needsProcessing(pf))
    }

    func testErroredUnratedLocalTakesTwinMemoIsNotDoubleHomed() {
        let id = UUID()
        let m = memo(id: id)
        let pf = file(isLocalRecording: true, error: "boom", transcribeStatus: .error)
        pf.id = id.uuidString
        XCTAssertTrue(WayOutRules.unpipelined(memos: [m], files: [pf]).isEmpty)
    }

    func testDeletedLocalRecordingNeverNeedsProcessing() {
        // The pre-existing soft-delete guard must still hold alongside the new one.
        let pf = file(isLocalRecording: true, significance: 0.5, deletedAt: Date())
        XCTAssertFalse(WayOutRules.needsProcessing(pf))
    }

    // MARK: - 5. the nil/zero-vs-0.1 edge, at the exact boundary the doctrine leans on

    func testLitCountEdgeNilAndZeroBothReadUnrated() {
        XCTAssertTrue(WayOutRules.isUnratedLocalRecording(file(isLocalRecording: true, significance: nil)))
        XCTAssertTrue(WayOutRules.isUnratedLocalRecording(file(isLocalRecording: true, significance: 0.0)))
    }

    func testLitCountEdgeOneTenthReadsRated() {
        XCTAssertFalse(WayOutRules.isUnratedLocalRecording(file(isLocalRecording: true, significance: 0.1)))
    }
}
