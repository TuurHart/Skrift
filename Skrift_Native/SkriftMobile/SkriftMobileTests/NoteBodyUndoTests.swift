import XCTest
import UIKit
@testable import SkriftMobile

/// Q536: the toolbar's checklist button, a checkbox tick and the Aa line styles are each ONE
/// step on the text view's undo stack (they used to edit `textStorage` directly, which UIKit's
/// undo manager never sees, so Undo skipped them).
@MainActor
final class NoteBodyUndoTests: XCTestCase {

    private func editor(_ body: String) -> (NoteBodyView.Coordinator, NoteBodyTextView) {
        let memo = Memo(audioFilename: "memo_q536.m4a", transcript: body)
        let coordinator = NoteBodyView.Coordinator(memo: memo, onCommit: { _ in })
        let tv = NoteBodyTextView()
        tv.installAccessoryHosts()
        coordinator.textView = tv
        coordinator.load(force: true)
        return (coordinator, tv)
    }

    /// What the note would store for the current text view contents.
    private func raw(_ c: NoteBodyView.Coordinator, _ tv: NoteBodyTextView) -> String {
        c.reconstruct(tv.attributedText)
    }

    func testAddingACheckboxUndoesAndRedoes() throws {
        let (c, tv) = editor("Buy milk\nBuy eggs")
        tv.selectedRange = NSRange(location: 3, length: 0)
        let before = raw(c, tv)
        let undo = try XCTUnwrap(tv.undoManager, "the text view has an undo manager")

        c.toggleChecklistAtCaret()
        let after = raw(c, tv)
        XCTAssertEqual(after, "- [ ] Buy milk\nBuy eggs")
        XCTAssertTrue(undo.canUndo, "the checklist button registered an undo step")

        c.undo()
        XCTAssertEqual(raw(c, tv), before, "line is back byte-for-byte")
        XCTAssertEqual(tv.text, "Buy milk\nBuy eggs")
        XCTAssertEqual(tv.selectedRange, NSRange(location: 3, length: 0), "caret restored")
        XCTAssertTrue(undo.canRedo)

        c.redo()
        XCTAssertEqual(raw(c, tv), after, "redo returns the checkbox")
    }

    func testRemovingACheckboxUndoes() throws {
        let (c, tv) = editor("- [ ] Buy milk")
        tv.selectedRange = NSRange(location: 3, length: 0)
        let before = raw(c, tv)
        XCTAssertEqual(before, "- [ ] Buy milk")

        c.toggleChecklistAtCaret()
        XCTAssertEqual(raw(c, tv), "Buy milk")
        c.undo()
        XCTAssertEqual(raw(c, tv), before)
        c.redo()
        XCTAssertEqual(raw(c, tv), "Buy milk")
    }

    func testTickingAnExistingCheckboxUndoes() throws {
        let (c, tv) = editor("- [ ] Buy milk\nBuy eggs")
        let before = raw(c, tv)

        c.toggleTask(at: 0)
        let ticked = raw(c, tv)
        XCTAssertEqual(ticked, "- [x] Buy milk\nBuy eggs")

        c.undo()
        XCTAssertEqual(raw(c, tv), before, "the tick is undone byte-for-byte")
        c.redo()
        XCTAssertEqual(raw(c, tv), ticked, "redo ticks it again")
    }

    func testALineStyleUndoes() throws {
        let (c, tv) = editor("Shopping\nBuy milk")
        tv.selectedRange = NSRange(location: 10, length: 0)
        let before = raw(c, tv)

        c.applyLineStyle(.heading)
        let styled = raw(c, tv)
        XCTAssertNotEqual(styled, before, "the style changed the line")

        c.undo()
        XCTAssertEqual(raw(c, tv), before)
        c.redo()
        XCTAssertEqual(raw(c, tv), styled)
    }
}
