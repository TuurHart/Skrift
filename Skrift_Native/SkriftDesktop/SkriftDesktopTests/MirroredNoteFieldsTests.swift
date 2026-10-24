import XCTest
import Foundation

/// The `PipelineFile` ⇄ `Memo` mirror declaration (2026-08-27, `ReconcileV2.Fields` since Q432),
/// which replaced hand-written copies in three files; Mac → phone is `ReconcileV2.Writers.pushMeta`. These tests exist because the two rules below are the ones a
/// future edit would quietly break — both have already cost a real bug once.
@MainActor
final class MirroredNoteFieldsTests: XCTestCase {

    @MainActor private func field(_ name: String) -> ReconcileV2.Field {
        ReconcileV2.Fields.all.first { $0.name == name }!
    }

    private func pair() -> (Memo, PipelineFile) {
        let id = UUID()
        let memo = Memo(id: id, audioFilename: "memo_\(id.uuidString).m4a")
        let pf = PipelineFile(id: id.uuidString, filename: "memo_\(id.uuidString).m4a")
        return (memo, pf)
    }

    // MARK: - Rule 1: a nil importance never rides the PASSIVE mirror

    /// `nil` is ambiguous on a `PipelineFile` — "cleared" OR "never rated". A Mac-local
    /// import sits at nil while its authored `Memo` carries a 0.1 rating, so
    /// pushing nil-as-0 on a passive pass would silently un-rate it on the next tag edit.
    /// Clearing is an EVENT (`MacCloudMetaSync.setRating`).
    @MainActor func testPassiveMirrorSkipsANilImportance() {
        let (memo, pf) = pair()
        memo.significance = 0.1
        pf.significance = nil

        XCTAssertFalse(ReconcileV2.Writers.pushMeta(pf, to: memo), "nothing to push")
        XCTAssertEqual(memo.significance, 0.1, "the authored floor survives a passive pass")
    }

    @MainActor func testPassiveMirrorPushesARealImportance() {
        let (memo, pf) = pair()
        pf.significance = 0.7
        XCTAssertTrue(ReconcileV2.Writers.pushMeta(pf, to: memo))
        XCTAssertEqual(memo.significance, 0.7)
        XCTAssertFalse(ReconcileV2.Writers.pushMeta(pf, to: memo), "already converged — no churn")
    }

    // MARK: - Rule 2: which fields the passive mirror carries at all

    /// Destination is EVENT-ONLY Mac→phone: it decides whether a note may leave for a repo
    /// an AI reads, so it lands the moment it is picked, not on the next unrelated tag edit.
    /// Lock and reminder are phone-authored — the Mac has no control that writes them.
    @MainActor func testOnlyTagsAndImportancePushFromTheMac() {
        let (memo, pf) = pair()
        pf.tags = ["kiln"]
        pf.significance = 0.4
        pf.destination = .portfolio
        pf.locked = true
        pf.remindAt = Date(timeIntervalSince1970: 1_800_000_000)
        XCTAssertTrue(ReconcileV2.Writers.pushMeta(pf, to: memo))
        XCTAssertEqual(memo.tags, ["kiln"])
        XCTAssertEqual(memo.significance, 0.4)
        XCTAssertNotEqual(memo.destination, .portfolio, "destination is an event")
        XCTAssertFalse(memo.locked)
        XCTAssertNil(memo.remindAt)
    }

    // MARK: - Rule 3: first contact must not wipe the Mac's tags

    /// `adopt` (ingest) differs from `pull` (live update) for exactly one field: a row can
    /// already carry applied tags when it is first matched to a memo, and an empty phone
    /// list is not a reason to clear them.
    @MainActor func testIngestNeverClearsTagsWithAnEmptyPhoneList() {
        let (memo, pf) = pair()
        pf.tags = ["work"]
        memo.tags = []

        XCTAssertFalse(field("tags").adopt(memo, pf), "first contact leaves them alone")
        XCTAssertEqual(pf.tags, ["work"])

        XCTAssertTrue(field("tags").pull(memo, pf), "…but a live edit that empties them lands")
        XCTAssertEqual(pf.tags, [])
    }

    @MainActor func testIngestAdoptsThePhonesTags() {
        let (memo, pf) = pair()
        memo.tags = ["lisbon", "furniture"]
        XCTAssertTrue(field("tags").adopt(memo, pf))
        XCTAssertEqual(pf.tags, ["lisbon", "furniture"])
    }

    // MARK: - Recompile classification

    /// Only the fields that reach the exported frontmatter force a recompile; the lock flag
    /// and the reminder are row state.
    @MainActor func testOnlyFrontmatterFieldsForceARecompile() {
        // Q511: `createdAt` and `titleIsHis` reach the frontmatter through export v2.
        XCTAssertEqual(Set(ReconcileV2.Fields.all.filter(\.recompiles).map(\.name)),
                       Set(["tags", "significance", "destination", "editedAt", "createdAt", "titleIsHis"]))
        XCTAssertEqual(Set(ReconcileV2.Fields.all.filter { !$0.recompiles }.map(\.name)),
                       Set(["locked", "remindAt"]))
    }

    /// Every pull is a no-op when the two sides already agree — the whole seam is
    /// content-compared so a Mac write and a phone write converge instead of clobbering.
    @MainActor func testEveryPullIsIdempotent() {
        for f in ReconcileV2.Fields.all {
            let (memo, pf) = pair()
            _ = f.pull(memo, pf)
            XCTAssertFalse(f.pull(memo, pf), "\(f.name) churned on an unchanged pair")
        }
    }
}
