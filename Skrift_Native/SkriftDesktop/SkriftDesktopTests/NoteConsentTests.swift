import XCTest
import SwiftData

/// The one rated/unrated predicate (`NoteConsent`) — the value table both
/// channels share, and the desktop adapter's three nil populations. These are
/// the rules every feature gate now routes through; if one of these moves,
/// every surface moves with it — which is the point.
final class NoteConsentTests: XCTestCase {

    // ── the value dialect (ThreeBallScale.step's reading, pinned from the consent side) ──

    func testValueTable() {
        XCTAssertFalse(NoteConsent.isRated(nil), "nil = never judged")
        XCTAssertFalse(NoteConsent.isRated(0), "0 = judged away / not judged — both unrated")
        XCTAssertTrue(NoteConsent.isRated(0.1), "the minimum real rating (the floors' value)")
        XCTAssertTrue(NoteConsent.isRated(0.7000000001), "float noise from old slider writes stays rated")
        XCTAssertTrue(NoteConsent.isRated(1.0))
        XCTAssertFalse(NoteConsent.isRated(Double.nan), "non-finite reads as unrated, never traps")
        XCTAssertFalse(NoteConsent.isRated(0.04), "below half a circle-step rounds to unrated")
    }

    func testMemoChannel() {
        XCTAssertFalse(NoteConsent.isRated(Memo(significance: 0)))
        XCTAssertTrue(NoteConsent.isRated(Memo(significance: 0.5)))
    }

    // ── the file channel: explicit values answer directly ──

    func testFileExplicitValues() {
        let pf = PipelineFile(id: UUID().uuidString)
        pf.significance = 0.6
        XCTAssertTrue(NoteConsent.isRated(pf))
        pf.significance = 0   // a synced row whose memo was un-rated (MemoCloudUpdate mirror)
        XCTAssertFalse(NoteConsent.isRated(pf), "a mirrored 0 is consent withdrawn")
    }

    // ── the three nil populations, resolved in one place ──

    /// A local RECORDING with no rating yet: unrated on purpose — capture is
    /// not judgment (the 2026-07-28 doctrine, `PipelineFile.isLocalRecording`).
    func testNilOnALocalRecordingIsUnrated() throws {
        let ctx = try Self.inMemoryContext()
        let pf = PipelineFile(id: UUID().uuidString)
        pf.isLocalRecording = true
        ctx.insert(pf)
        XCTAssertNil(pf.significance)
        XCTAssertFalse(NoteConsent.isRated(pf))
    }

    /// A local IMPORT / legacy row: its authored `Memo` carries the 0.1 floor
    /// (`MacMemoAuthor` — adding a file IS a request to process it); the row's
    /// nil just means it never heard the number back. Reading it as unrated
    /// would silently drop every Mac import out of processing/connections —
    /// the exact trap `MacCloudMetaSync.mirror` documents.
    func testNilOnAnInsertedImportIsRated() throws {
        let ctx = try Self.inMemoryContext()
        let pf = PipelineFile(id: UUID().uuidString)
        ctx.insert(pf)
        XCTAssertNil(pf.significance)
        XCTAssertFalse(pf.isLocalRecording)
        XCTAssertTrue(NoteConsent.isRated(pf))
    }

    /// A PROJECTION (`MemoNoteProjection` — never inserted, `modelContext`
    /// stays nil): it maps an unrated memo's 0 to nil, so nil here means the
    /// memo's truth was 0 → unrated. The nil-modelContext capability test is
    /// the established projection marker (`MacCloudEditSync` precedent).
    func testNilOnAProjectionIsUnrated() {
        let pf = PipelineFile(id: UUID().uuidString)
        XCTAssertNil(pf.modelContext)
        XCTAssertFalse(NoteConsent.isRated(pf))
    }

    /// A projection of a RATED memo carries the value and never consults the
    /// context — rating a note in the unrated pane flips this live.
    func testRatedProjectionIsRated() {
        let pf = PipelineFile(id: UUID().uuidString)
        pf.significance = 0.3
        XCTAssertTrue(NoteConsent.isRated(pf))
    }

    // ── equivalence with the file-channel gate it feeds ──

    /// `WayOutRules.isUnratedLocalRecording` must agree with the adapter for
    /// every recording state (nil / 0 / rated) — it's the same rule now.
    func testAgreesWithWayOutRulesForRecordings() throws {
        let ctx = try Self.inMemoryContext()
        for sig: Double? in [nil, 0, 0.4] {
            let pf = PipelineFile(id: UUID().uuidString)
            pf.isLocalRecording = true
            pf.significance = sig
            ctx.insert(pf)
            XCTAssertEqual(WayOutRules.isUnratedLocalRecording(pf), !NoteConsent.isRated(pf),
                           "disagreement at significance \(String(describing: sig))")
        }
    }

    // ── connections-index membership (ROUND 9 item 4 — the Mac's index gate) ──

    /// An unrated Mac take must never join the idea graph; rating it admits it;
    /// un-rating (a mirrored 0) withdraws it; trash always excludes. The sweep's
    /// orphan pass turns "not a member" into row removal, so this predicate IS
    /// the graph membership rule.
    func testConnectionsIndexMembership() throws {
        let ctx = try Self.inMemoryContext()

        let take = PipelineFile(id: UUID().uuidString)
        take.isLocalRecording = true
        ctx.insert(take)
        XCTAssertFalse(NoteConsent.joinsConnectionsIndex(take),
                       "an unrated take with words is still not a member")

        take.significance = 0.3
        XCTAssertTrue(NoteConsent.joinsConnectionsIndex(take), "rating admits it")

        take.significance = 0
        XCTAssertFalse(NoteConsent.joinsConnectionsIndex(take), "un-rating withdraws it")

        let synced = PipelineFile(id: UUID().uuidString)
        synced.significance = 0.6
        ctx.insert(synced)
        XCTAssertTrue(NoteConsent.joinsConnectionsIndex(synced))
        synced.deletedAt = Date()
        XCTAssertFalse(NoteConsent.joinsConnectionsIndex(synced), "trash always excludes")

        let importRow = PipelineFile(id: UUID().uuidString)   // nil significance, 0.1-floor authored
        ctx.insert(importRow)
        XCTAssertTrue(NoteConsent.joinsConnectionsIndex(importRow),
                      "a Mac import (rated by authoring) stays in the graph")
    }

    private static func inMemoryContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: PipelineFile.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        return ModelContext(container)
    }
}
