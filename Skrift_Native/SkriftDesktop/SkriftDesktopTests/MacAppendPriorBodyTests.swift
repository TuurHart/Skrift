import XCTest

/// Q532: while "Add recording" is live, the pane shows the note's existing body read-only above
/// the new words. A fresh take shows no prior body. The landed text (`joined`) is unchanged.
final class MacAppendPriorBodyTests: XCTestCase {

    func testAppendOverNoteWithBodyShowsThatBody() {
        XCTAssertEqual(MacAppendRecording.priorBody(isAppending: true, body: "A"), "A")
    }

    func testBodyIsTrimmedButOtherwiseVerbatim() {
        XCTAssertEqual(MacAppendRecording.priorBody(isAppending: true, body: "\n One.\n\nTwo. \n"),
                       "One.\n\nTwo.")
    }

    func testFreshTakeShowsNoPriorBody() {
        XCTAssertNil(MacAppendRecording.priorBody(isAppending: false, body: "A"))
    }

    func testAppendOverEmptyOrNilBodyShowsNothing() {
        XCTAssertNil(MacAppendRecording.priorBody(isAppending: true, body: "  \n"))
        XCTAssertNil(MacAppendRecording.priorBody(isAppending: true, body: nil))
    }

    func testLandedResultIsStillBodyBlankLineNewWords() {
        XCTAssertEqual(MacAppendRecording.joined("A", "new words"), "A\n\nnew words")
    }
}
