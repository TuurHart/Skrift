import SwiftUI
import UIKit
import XCTest
@testable import SkriftMobile

/// C261 / R70 on the phone and iPad editor: a commit that nets to empty never lands silently.
/// With no window to ask in (a unit test host), the confirm cannot be shown, so the prior text
/// stays and goes back on screen.
final class EmptyCommitEditorTests: XCTestCase {

    @MainActor
    private func makeEditor(transcript: String) -> (NoteBodyView.Coordinator, NoteBodyTextView) {
        let memo = Memo(audioFilename: "memo_clear.m4a", transcript: transcript)
        let coordinator = NoteBodyView.Coordinator(memo: memo, onCommit: { _ in })
        let tv = NoteBodyTextView()
        tv.installAccessoryHosts()
        coordinator.textView = tv
        coordinator.load(force: true)
        return (coordinator, tv)
    }

    // editor-clear-raw
    @MainActor
    func testClearingRawKeepsPriorTextWhenItCannotAsk() {
        let (coordinator, tv) = makeEditor(transcript: "hello world")
        tv.attributedText = NSAttributedString(string: "   ")
        coordinator.textViewDidChange(tv)
        coordinator.commitDraft()
        XCTAssertEqual(coordinator.memo.transcript, "hello world", "an emptying commit must not land unasked")
        XCTAssertEqual(tv.text, "hello world", "the prior text goes back on screen")
    }

    // editor-clear-polished
    @MainActor
    func testClearingPolishedKeepsPriorTextWhenItCannotAsk() {
        let (coordinator, tv) = makeEditor(transcript: "raw words")
        var polished = "the polished note"
        coordinator.polishedBinding = Binding(get: { polished }, set: { polished = $0 })
        coordinator.load(force: true)
        tv.attributedText = NSAttributedString(string: "")
        coordinator.textViewDidChange(tv)
        coordinator.commitDraft()
        XCTAssertEqual(polished, "the polished note")
        XCTAssertEqual(coordinator.memo.transcript, "raw words")
    }

    @MainActor
    func testDebouncedEmptyDraftWaitsInsteadOfWriting() {
        let (coordinator, tv) = makeEditor(transcript: "hello world")
        tv.attributedText = NSAttributedString(string: "")
        coordinator.textViewDidChange(tv)
        coordinator.commitDraft(debounced: true)
        XCTAssertEqual(coordinator.memo.transcript, "hello world")
        XCTAssertEqual(tv.text, "", "mid-typing the view is left alone so the user can retype")
        tv.attributedText = NSAttributedString(string: "fresh start")
        coordinator.textViewDidChange(tv)
        coordinator.commitDraft(debounced: true)
        XCTAssertEqual(coordinator.memo.transcript, "fresh start", "retyping commits normally")
    }
}
