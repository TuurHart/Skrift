import UIKit
import XCTest
@testable import SkriftMobile

/// Q123 (C10, C19): the end-of-edit normalisation is ONE rule on both devices. The phone's
/// `commitDraft` used to call `BodyV2.committed` only for a body with picture runs, so a plain
/// typed body kept its double spaces and blank-line runs while the Mac's end-of-editing commit
/// (`BodyV2.committed(Input(text:, source: .typed))`) stored them tidied.
final class PhoneEndOfEditNormaliseTests: XCTestCase {

    private let messy = "one  two\t\tthree\n\n\n\nfour   five\r\n\r\n\r\nsix  "

    /// What the Mac's `BodyTextView.textDidEndEditing` stores for these keystrokes.
    private var macStores: String {
        BodyV2.committed(BodyV2.Input(text: messy, source: .typed))
    }

    @MainActor
    private func phoneStores(audioFilename: String) -> String? {
        let memo = Memo(audioFilename: audioFilename, transcript: "seed")
        let coordinator = NoteBodyView.Coordinator(memo: memo, onCommit: {})
        let tv = NoteBodyTextView()
        tv.installAccessoryHosts()
        coordinator.textView = tv
        coordinator.load(force: true)
        tv.attributedText = NSAttributedString(string: messy)
        coordinator.textViewDidChange(tv)
        coordinator.commitDraft()
        return memo.transcript
    }

    @MainActor
    func testTypedBodyStoresWhatTheMacStores() {
        let stored = phoneStores(audioFilename: "")
        XCTAssertEqual(stored, macStores)
        XCTAssertEqual(stored, "one two three\n\nfour five\n\nsix")
    }

    @MainActor
    func testVoiceNoteBodyStoresWhatTheMacStores() {
        XCTAssertEqual(phoneStores(audioFilename: "memo_edit.m4a"), macStores)
    }
}
