import XCTest
import Foundation

/// The `PipelineFile` ⇄ `Memo` mirror declaration (2026-08-27), which replaced hand-written
/// copies in three files. These tests exist because the two rules below are the ones a
/// future edit would quietly break — both have already cost a real bug once.
final class MirroredNoteFieldsTests: XCTestCase {

    private func field(_ name: String) -> MirroredNoteFields.Field {
        MirroredNoteFields.all.first { $0.name == name }!
    }

    private func pair() -> (Memo, PipelineFile) {
        let id = UUID()
        let memo = Memo(id: id, audioFilename: "memo_\(id.uuidString).m4a")
        let pf = PipelineFile(id: id.uuidString, filename: "memo_\(id.uuidString).m4a")
        return (memo, pf)
    }

    // MARK: - Rule 1: a nil importance never rides the PASSIVE mirror

    /// `nil` is ambiguous on a `PipelineFile` — "cleared" OR "never rated". A Mac-local
    /// import sits at nil while its authored `Memo` carries `MacMemoAuthor`'s 0.1 floor, so
    /// pushing nil-as-0 on a passive pass would silently un-rate it on the next tag edit.
    /// Clearing is an EVENT (`MacCloudMetaSync.setRating`).
    func testPassiveMirrorSkipsANilImportance() {
        let (memo, pf) = pair()
        memo.significance = 0.1
        pf.significance = nil

        XCTAssertFalse(field("significance").push!(pf, memo), "nothing to push")
        XCTAssertEqual(memo.significance, 0.1, "the authored floor survives a passive pass")
    }

    func testPassiveMirrorPushesARealImportance() {
        let (memo, pf) = pair()
        pf.significance = 0.7
        XCTAssertTrue(field("significance").push!(pf, memo))
        XCTAssertEqual(memo.significance, 0.7)
        XCTAssertFalse(field("significance").push!(pf, memo), "already converged — no churn")
    }

    // MARK: - Rule 2: which fields the passive mirror carries at all

    /// Destination is EVENT-ONLY Mac→phone: it decides whether a note may leave for a repo
    /// an AI reads, so it lands the moment it is picked, not on the next unrelated tag edit.
    /// Lock and reminder are phone-authored — the Mac has no control that writes them.
    func testOnlyTagsAndImportancePushFromTheMac() {
        XCTAssertEqual(Set(MirroredNoteFields.pushable.map(\.name)), ["tags", "significance"])
        XCTAssertNil(field("destination").push)
        XCTAssertNil(field("locked").push)
        XCTAssertNil(field("remindAt").push)
    }

    // MARK: - Rule 3: first contact must not wipe the Mac's tags

    /// `adopt` (ingest) differs from `pull` (live update) for exactly one field: a row can
    /// already carry applied tags when it is first matched to a memo, and an empty phone
    /// list is not a reason to clear them.
    func testIngestNeverClearsTagsWithAnEmptyPhoneList() {
        let (memo, pf) = pair()
        pf.tags = ["work"]
        memo.tags = []

        XCTAssertFalse(field("tags").adopt(memo, pf), "first contact leaves them alone")
        XCTAssertEqual(pf.tags, ["work"])

        XCTAssertTrue(field("tags").pull(memo, pf), "…but a live edit that empties them lands")
        XCTAssertEqual(pf.tags, [])
    }

    func testIngestAdoptsThePhonesTags() {
        let (memo, pf) = pair()
        memo.tags = ["lisbon", "furniture"]
        XCTAssertTrue(field("tags").adopt(memo, pf))
        XCTAssertEqual(pf.tags, ["lisbon", "furniture"])
    }

    // MARK: - Recompile classification

    /// Only the fields that reach the exported frontmatter force a recompile; the lock flag
    /// and the reminder are row state.
    func testOnlyFrontmatterFieldsForceARecompile() {
        XCTAssertEqual(Set(MirroredNoteFields.all.filter(\.recompiles).map(\.name)),
                       ["tags", "significance", "destination", "editedAt"])
        XCTAssertEqual(Set(MirroredNoteFields.all.filter { !$0.recompiles }.map(\.name)),
                       ["locked", "remindAt"])
    }

    /// Every pull is a no-op when the two sides already agree — the whole seam is
    /// content-compared so a Mac write and a phone write converge instead of clobbering.
    func testEveryPullIsIdempotent() {
        for f in MirroredNoteFields.all {
            let (memo, pf) = pair()
            _ = f.pull(memo, pf)
            XCTAssertFalse(f.pull(memo, pf), "\(f.name) churned on an unchanged pair")
        }
    }
}
