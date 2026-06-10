import UIKit
import XCTest
@testable import SkriftMobile

/// Regression tests for the "paste teleports the note to the top" bug: the
/// self-sizing text view must never honour UIKit's internal caret-scroll offsets,
/// and a rebuild of the attributed text must carry the caret across (a caret
/// reset to 0 is what SwiftUI's keyboard avoidance scrolls to).
final class TranscriptEditorTests: XCTestCase {

    @MainActor
    private func makeEditor(transcript: String) -> (TranscriptEditor.Coordinator, UITextView) {
        let memo = Memo(audioFilename: "memo_edit.m4a", transcript: transcript)
        let coordinator = TranscriptEditor.Coordinator(memo: memo, onCommit: {}, width: 350)
        let tv = NonScrollingTextView()
        tv.isScrollEnabled = false
        coordinator.textView = tv
        coordinator.load(force: true)
        return (coordinator, tv)
    }

    @MainActor
    func testRebuildPreservesCaretPosition() {
        let (coordinator, tv) = makeEditor(transcript: "one two three four five")
        tv.selectedRange = NSRange(location: 8, length: 0)
        coordinator.memo.transcript = "one two three four five six"   // changed under us
        coordinator.load(force: false)
        XCTAssertEqual(tv.text, "one two three four five six")        // rebuilt
        XCTAssertEqual(tv.selectedRange, NSRange(location: 8, length: 0))
    }

    @MainActor
    func testRebuildClampsCaretWhenTextShrinks() {
        let (coordinator, tv) = makeEditor(transcript: "a long transcript body")
        tv.selectedRange = NSRange(location: 20, length: 0)
        coordinator.memo.transcript = "tiny"
        coordinator.load(force: false)
        XCTAssertEqual(tv.text, "tiny")
        XCTAssertEqual(tv.selectedRange, NSRange(location: 4, length: 0))
    }

    @MainActor
    func testTextViewDidChangeWritesBackAndFlagsUserEdited() {
        let (coordinator, tv) = makeEditor(transcript: "hello world")
        tv.attributedText = NSAttributedString(string: "hello brave world")
        coordinator.textViewDidChange(tv)
        XCTAssertEqual(coordinator.memo.transcript, "hello brave world")
        XCTAssertTrue(coordinator.memo.transcriptUserEdited)
        XCTAssertEqual(coordinator.memo.transcriptStatus, .done)
    }

    @MainActor
    func testNonScrollingTextViewPinsInternalScrollOffset() {
        let tv = NonScrollingTextView(frame: CGRect(x: 0, y: 0, width: 320, height: 80))
        tv.isScrollEnabled = false
        tv.text = Array(repeating: "lorem ipsum dolor", count: 100).joined(separator: " ")
        // What UIKit does internally on paste: a caret-scroll against stale bounds.
        tv.setContentOffset(CGPoint(x: 0, y: 400), animated: false)
        XCTAssertEqual(tv.contentOffset, .zero)
        tv.contentOffset = CGPoint(x: 0, y: 250)                      // property-setter path
        XCTAssertEqual(tv.contentOffset, .zero)
        // Re-enabled scrolling behaves like a normal text view again.
        tv.isScrollEnabled = true
        tv.setContentOffset(CGPoint(x: 0, y: 40), animated: false)
        XCTAssertEqual(tv.contentOffset.y, 40)
    }
}
