import XCTest
import UIKit
@testable import SkriftMobile

/// Q79 (C112/C113): while the user edits, the UITextView is the source of truth, so a
/// stale binding (lagging a keystroke behind, as it does while the first keystroke
/// creates the draft Memo) can never be written back over what was typed.
@MainActor
final class QuickNoteBodyTextViewTests: XCTestCase {

    func testStaleBindingNeverOverwritesWhileEditing() {
        XCTAssertFalse(QuickNoteBodyTextView.shouldPush(
            bound: "Tram 28 idea", current: "Tram 28 idea\n", isEditing: true, hasMarkedText: false))
    }

    func testBindingNeverOverwritesAnIMEComposition() {
        XCTAssertFalse(QuickNoteBodyTextView.shouldPush(
            bound: "a", current: "ab", isEditing: false, hasMarkedText: true))
    }

    func testBindingStillPushesWhenNobodyIsEditing() {
        XCTAssertTrue(QuickNoteBodyTextView.shouldPush(
            bound: "restored", current: "", isEditing: false, hasMarkedText: false))
    }

    func testEqualTextIsNeverRewritten() {
        XCTAssertFalse(QuickNoteBodyTextView.shouldPush(
            bound: "same", current: "same", isEditing: false, hasMarkedText: false))
    }

    /// A real text view with a real Return typed into it, then a stale binding offered.
    func testRealTextViewKeepsTypedReturnAgainstStaleBinding() {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
        let tv = UITextView(frame: window.bounds)
        window.addSubview(tv)
        window.makeKeyAndVisible()
        _ = tv.becomeFirstResponder()
        tv.insertText("Tram 28 idea")
        let staleBinding = "Tram 28 idea"
        tv.insertText("\n")
        if QuickNoteBodyTextView.shouldPush(bound: staleBinding, current: tv.text,
                                            isEditing: tv.isFirstResponder,
                                            hasMarkedText: tv.markedTextRange != nil) {
            tv.text = staleBinding
        }
        XCTAssertEqual(tv.text, "Tram 28 idea\n")
    }
}
