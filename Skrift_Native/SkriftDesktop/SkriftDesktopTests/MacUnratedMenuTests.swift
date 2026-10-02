import XCTest

/// Q127 (C40/D159/C187): an unrated Mac note's ⋯ offers Process, Lock and Delete beside the
/// copies, the same verbs the iPad's ⋯ carries; Process floors the rating through `NoteConsent`.
final class MacUnratedMenuTests: XCTestCase {

    func testUnratedMenuHasProcessLockCopyDeleteInOrder() {
        let e = MacUnratedMenu.entries(rated: false, locked: false, canUndoTidyUp: false)
        XCTAssertEqual(e, [.process, .item(.lock), .item(.copyTranscript), .item(.copyMarkdown), .item(.delete)])
    }

    func testLockedNoteOffersRemoveLockNotLock() {
        let e = MacUnratedMenu.entries(rated: false, locked: true, canUndoTidyUp: false)
        XCTAssertTrue(e.contains(.item(.unlock)))
        XCTAssertFalse(e.contains(.item(.lock)))
        XCTAssertTrue(e.contains(.process), "a locked note is still in the process queue (C182, lock is about eyes)")
    }

    func testUndoTidyUpOnlyWhenOffered() {
        XCTAssertTrue(MacUnratedMenu.entries(rated: false, locked: false, canUndoTidyUp: true).contains(.item(.undoTidyUp)))
        XCTAssertFalse(MacUnratedMenu.entries(rated: false, locked: false, canUndoTidyUp: false).contains(.item(.undoTidyUp)))
    }

    func testRatedProjectionIsNotOfferedProcessAgain() {
        let e = MacUnratedMenu.entries(rated: true, locked: false, canUndoTidyUp: false)
        XCTAssertFalse(e.contains(.process))
        XCTAssertTrue(e.contains(.item(.delete)), "lock and delete stay: the note still has no row to act on")
    }

    func testDeleteIsLastAndLabelsComeFromTheSharedTables() {
        let e = MacUnratedMenu.entries(rated: false, locked: false, canUndoTidyUp: true)
        XCTAssertEqual(e.last, .item(.delete))
        XCTAssertEqual(MacUnratedMenu.label(.process), SharedCopy.processVerb)
        XCTAssertEqual(MacUnratedMenu.label(.item(.delete)), NoteMenuItem.delete.label)
        XCTAssertEqual(MacUnratedMenu.label(.item(.lock)), NoteMenuItem.lock.label)
    }

    // ── Process floors the rating through NoteConsent (C40) ──

    func testProcessFloorsAnUnratedNoteToPointOne() {
        XCTAssertEqual(NoteConsent.flooredByProcess(nil), 0.1)
        XCTAssertEqual(NoteConsent.flooredByProcess(0), 0.1)
        XCTAssertEqual(NoteConsent.flooredByProcess(0.04), 0.1, "below half a circle-step is still unrated")
        XCTAssertTrue(NoteConsent.isRated(NoteConsent.flooredByProcess(nil)), "the floor IS a judgment")
    }

    func testProcessNeverLowersAnExistingRating() {
        XCTAssertEqual(NoteConsent.flooredByProcess(0.7), 0.7)
        XCTAssertEqual(NoteConsent.flooredByProcess(1.0), 1.0)
    }
}
