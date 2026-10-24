import XCTest
import UIKit
@testable import SkriftMobile

/// Q520: picking a note link keeps the space after the chip for the next word. The stored body
/// is trimmed at commit (C19 "ends trimmed"); the editor's in-session text is exempt, so the
/// space lives in the text view, the caret sits after it, and the next word lands after it.
@MainActor
final class MemoLinkSpaceTests: XCTestCase {

    private let idA = UUID(uuidString: "AAAAAAAA-1111-2222-3333-444444444444")!

    private func editorAfterPickingALink(_ body: String) -> (Memo, NoteBodyView.Coordinator, NoteBodyTextView) {
        let memo = Memo(audioFilename: "memo_q520.m4a", transcript: body)
        let coordinator = NoteBodyView.Coordinator(memo: memo, onCommit: { _ in })
        let tv = NoteBodyTextView()
        tv.installAccessoryHosts()
        coordinator.textView = tv
        coordinator.load(force: true)
        tv.textStorage.append(NSAttributedString(string: "[["))
        tv.selectedRange = NSRange(location: tv.textStorage.length, length: 0)
        coordinator.textViewDidChange(tv)
        coordinator.insertMemoLink(id: idA, title: "Harbor")
        return (memo, coordinator, tv)
    }

    private func type(_ s: String, into tv: NoteBodyTextView, _ coordinator: NoteBodyView.Coordinator) {
        tv.textStorage.insert(NSAttributedString(string: s), at: tv.selectedRange.location)
        tv.selectedRange = NSRange(location: tv.selectedRange.location + (s as NSString).length, length: 0)
        coordinator.textViewDidChange(tv)
        coordinator.commitDraft()
    }

    func testTheSpaceStaysInTheEditorWithTheCaretAfterIt() {
        let (memo, coordinator, tv) = editorAfterPickingALink("Hello ")
        XCTAssertEqual(memo.transcript, "Hello [[memo:\(idA.uuidString)|Harbor]]", "stored trimmed (C19)")
        XCTAssertTrue(tv.text.hasSuffix("\u{FFFC} "), "the chip, then the space: \(tv.text.debugDescription)")
        XCTAssertEqual(tv.selectedRange, NSRange(location: tv.textStorage.length, length: 0), "caret after the space")
        coordinator.load(force: false)       // what every updateUIView does after the commit
        XCTAssertTrue(tv.text.hasSuffix("\u{FFFC} "), "a re-render keeps the space")
    }

    func testTheNextWordLandsAfterTheSpace() {
        let (memo, coordinator, tv) = editorAfterPickingALink("Hello ")
        coordinator.load(force: false)
        type("world", into: tv, coordinator)
        XCTAssertEqual(memo.transcript, "Hello [[memo:\(idA.uuidString)|Harbor]] world")
    }

    func testAPickMidSentenceLeavesOneSpace() {
        let memo = Memo(audioFilename: "memo_q520b.m4a", transcript: "Hello there")
        let coordinator = NoteBodyView.Coordinator(memo: memo, onCommit: { _ in })
        let tv = NoteBodyTextView()
        tv.installAccessoryHosts()
        coordinator.textView = tv
        coordinator.load(force: true)
        tv.textStorage.insert(NSAttributedString(string: "[["), at: 6)
        tv.selectedRange = NSRange(location: 8, length: 0)
        coordinator.textViewDidChange(tv)
        coordinator.insertMemoLink(id: idA, title: "Harbor")
        XCTAssertEqual(memo.transcript, "Hello [[memo:\(idA.uuidString)|Harbor]] there")
    }
}
