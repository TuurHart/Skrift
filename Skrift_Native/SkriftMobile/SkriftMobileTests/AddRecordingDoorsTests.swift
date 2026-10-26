import XCTest
@testable import SkriftMobile

/// Q527: Add recording has exactly one door per note. The + button where it shows (compact width,
/// saved note, not a share capture); the ⋯ entry everywhere else.
final class AddRecordingDoorsTests: XCTestCase {

    func testCompactSavedNoteHasPlusAndNoMenuEntry() {
        XCTAssertTrue(AddRecordingDoors.showsPlusButton(isCompactWidth: true, isPendingDraft: false, isShareCapture: false))
        XCTAssertFalse(AddRecordingDoors.showsMenuEntry(isCompactWidth: true, isPendingDraft: false, isShareCapture: false),
                       "the ⋯ menu must not repeat what the + does")
    }

    func testRegularWidthHasNoPlusSoMenuKeepsTheEntry() {
        XCTAssertFalse(AddRecordingDoors.showsPlusButton(isCompactWidth: false, isPendingDraft: false, isShareCapture: false))
        XCTAssertTrue(AddRecordingDoors.showsMenuEntry(isCompactWidth: false, isPendingDraft: false, isShareCapture: false))
    }

    func testEveryCaseHasExactlyOneDoor() {
        for compact in [true, false] { for draft in [true, false] { for share in [true, false] {
            let plus = AddRecordingDoors.showsPlusButton(isCompactWidth: compact, isPendingDraft: draft, isShareCapture: share)
            let menu = AddRecordingDoors.showsMenuEntry(isCompactWidth: compact, isPendingDraft: draft, isShareCapture: share)
            if share {
                XCTAssertFalse(plus || menu, "a share capture has no door: compact=\(compact) draft=\(draft)")
            } else {
                XCTAssertNotEqual(plus, menu, "compact=\(compact) draft=\(draft)")
            }
        } } }
    }

    func testShareCaptureAndPendingDraftNeverShowPlus() {
        XCTAssertFalse(AddRecordingDoors.showsPlusButton(isCompactWidth: true, isPendingDraft: false, isShareCapture: true))
        XCTAssertFalse(AddRecordingDoors.showsPlusButton(isCompactWidth: true, isPendingDraft: true, isShareCapture: false))
    }
}
