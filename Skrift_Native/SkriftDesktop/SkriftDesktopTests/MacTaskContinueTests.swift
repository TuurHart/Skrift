import XCTest

/// Q126: the shared Return-on-a-checklist-line rule (`BodyTransform.taskReturn`) that the
/// Mac editor now runs and the phone shares. Display text: each box is one U+FFFC glyph.
final class MacTaskContinueTests: XCTestCase {
    private let box = "\u{FFFC}"

    private func rule(_ text: String, caret: Int, boxIndex: Int) -> BodyTransform.TaskReturn {
        BodyTransform.taskReturn(in: text as NSString, caret: caret, boxIndex: boxIndex)
    }

    func testReturnAtEndOfItemContinuesTheList() {
        let t = "\(box) buy milk"
        let r = rule(t, caret: (t as NSString).length, boxIndex: 0)
        XCTAssertEqual(r, .continued(removeSpace: nil, insertAt: (t as NSString).length, lead: "\n"))
    }

    func testReturnMidItemSplitsAndTrimsTheSpaceAfterTheCaret() {
        let t = "\(box) buy milk"                  // caret after "buy"
        let r = rule(t, caret: 5, boxIndex: 0)
        XCTAssertEqual(r, .continued(removeSpace: NSRange(location: 5, length: 1), insertAt: 5, lead: "\n"))
    }

    func testReturnOnEmptyItemEndsTheList() {
        let t = "\(box) \nnext"
        XCTAssertEqual(rule(t, caret: 2, boxIndex: 0), .dissolve(range: NSRange(location: 0, length: 2)))
        let bare = box
        XCTAssertEqual(rule(bare, caret: 1, boxIndex: 0), .dissolve(range: NSRange(location: 0, length: 1)))
    }

    func testWhitespaceOnlyItemCountsAsEmpty() {
        let t = "\(box)   "
        XCTAssertEqual(rule(t, caret: 4, boxIndex: 0), .dissolve(range: NSRange(location: 0, length: 4)))
    }

    func testIndentIsCopiedOntoTheNewItem() {
        let t = "  \(box) sub item"
        let r = rule(t, caret: (t as NSString).length, boxIndex: 2)
        XCTAssertEqual(r, .continued(removeSpace: nil, insertAt: (t as NSString).length, lead: "\n  "))
    }

    func testSecondLineIsJudgedOnItsOwnLine() {
        let t = "intro\n\(box) one\n\(box) two"
        let boxIndex = ("intro\n\(box) one\n" as NSString).length
        let r = rule(t, caret: (t as NSString).length, boxIndex: boxIndex)
        XCTAssertEqual(r, .continued(removeSpace: nil, insertAt: (t as NSString).length, lead: "\n"))
    }

    func testCaretBeforeTheBoxIsAPlainNewline() {
        let t = "\(box) buy milk"
        XCTAssertEqual(rule(t, caret: 0, boxIndex: 0), .passthrough)
    }

    func testBoxOnAnotherLineIsNotOurs() {
        let t = "plain line\n\(box) task"
        XCTAssertEqual(rule(t, caret: 4, boxIndex: 11), .passthrough)
    }

    func testOutOfRangeBoxIndexIsPassthrough() {
        XCTAssertEqual(rule("", caret: 0, boxIndex: 0), .passthrough)
        XCTAssertEqual(rule("abc", caret: 1, boxIndex: 9), .passthrough)
    }
}
