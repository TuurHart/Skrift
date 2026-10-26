import SwiftUI
import UIKit
import XCTest
@testable import SkriftMobile

/// Q523: a person added from an open note turns their name purple at once. The page re-derives
/// the name spans when the names list changes; the body must restyle then, even while the
/// writer still holds a selection (the "New person…" text-menu path) or the keyboard.
final class NoteBodyNameRefreshTests: XCTestCase {

    @MainActor
    private func makeEditor(_ text: String) -> (NoteBodyView.Coordinator, NoteBodyTextView) {
        let memo = Memo(audioFilename: "memo_q523.m4a", transcript: text)
        let coordinator = NoteBodyView.Coordinator(memo: memo, onCommit: { _ in })
        let tv = NoteBodyTextView()
        tv.installAccessoryHosts()
        coordinator.textView = tv
        coordinator.load(force: true)
        return (coordinator, tv)
    }

    private func foreground(_ tv: NoteBodyTextView, at index: Int) -> UIColor? {
        tv.textStorage.attribute(.foregroundColor, at: index, effectiveRange: nil) as? UIColor
    }

    @MainActor
    func testAddingAPersonRestylesTheOpenNoteBodyAtOnce() {
        let text = "I talked to testing about lunch"
        let (c, tv) = makeEditor(text)
        let nameAt = (text as NSString).range(of: "testing").location
        // The writer selected the word to add it: the selection is still live afterwards.
        tv.selectedRange = NSRange(location: nameAt, length: 7)

        let testing = Person(canonical: "[[Testing]]", aliases: ["Testing"], short: nil,
                             lastModifiedAt: "2026-10-26T00:00:00.000Z")
        let spans = Sanitiser.nameSpans(inRaw: text, people: [testing])
        XCTAssertFalse(spans.isEmpty, "the new person's name is found in the body")
        let linked = UIColor(Color.skNameLinked)

        // The quiet rule alone (selection live, so not quiet) stores the spans unstyled.
        c.receiveSpans(spans, restyleToken: 0, quiet: false)
        XCTAssertNotEqual(foreground(tv, at: nameAt), linked)

        // The page bumps the token on a names change: the name is linked right now.
        c.receiveSpans(spans, restyleToken: 1, quiet: false)
        XCTAssertEqual(foreground(tv, at: nameAt), linked)
        XCTAssertNotEqual(foreground(tv, at: 0), linked, "words that are not the name stay plain")
    }

    @MainActor
    func testDeletingTheLastPersonClearsTheNameStyling() {
        let text = "I talked to testing about lunch"
        let (c, tv) = makeEditor(text)
        let nameAt = (text as NSString).range(of: "testing").location
        tv.selectedRange = NSRange(location: nameAt, length: 7)
        let testing = Person(canonical: "[[Testing]]", aliases: ["Testing"], short: nil,
                             lastModifiedAt: "2026-10-26T00:00:00.000Z")
        c.receiveSpans(Sanitiser.nameSpans(inRaw: text, people: [testing]), restyleToken: 1, quiet: false)
        XCTAssertEqual(foreground(tv, at: nameAt), UIColor(Color.skNameLinked))

        c.receiveSpans([], restyleToken: 2, quiet: false)
        XCTAssertNotEqual(foreground(tv, at: nameAt), UIColor(Color.skNameLinked))
    }
}
