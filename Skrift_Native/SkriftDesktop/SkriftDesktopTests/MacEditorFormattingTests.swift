import XCTest
import Foundation

/// Q360 (D115, D193, D196, C234; signed mock `mocks/Q350-note-editor-apple.html`): the Mac
/// note editor's formatting. The verbs are pure edits on the stored Markdown (C116), so the
/// editor stays WYSIWYG to the export: Bold writes `**…**`, Italic `*…*`, Underline
/// `<u>…</u>`, Strikethrough `~~…~~`, Title `# `, Heading `## `, lists `- ` / `1. `.
/// The text view (`BodyTextView`, AppKit) is not compiled into this host-less bundle; it
/// applies exactly these edits, and the full SkriftDesktop build proves the wiring.
final class MacEditorFormattingTests: XCTestCase {

    // MARK: - mark pairs: found, dimmed, styled (C24/C116)

    func testEveryMarkPairIsFoundWithItsTwoMarksAndItsInnerText() {
        let text = "a **bold** b *it* c <u>under</u> d ~~gone~~ e"
        let spans = BodyFormat.spans(in: text)
        let ns = text as NSString
        XCTAssertEqual(spans.map(\.mark), [.bold, .italic, .underline, .strike])
        for s in spans {
            XCTAssertEqual(ns.substring(with: s.open), s.mark.open)
            XCTAssertEqual(ns.substring(with: s.close), s.mark.close)
        }
        XCTAssertEqual(spans.map { ns.substring(with: $0.inner) }, ["bold", "it", "under", "gone"])
    }

    func testUnderlineIsAMarkPairSoBothTagsDim() {
        let text = "the <u>spindle</u> mount"
        let span = try? XCTUnwrap(BodyFormat.spans(in: text).first)
        XCTAssertEqual(span?.mark, .underline)
        XCTAssertEqual(span?.open, NSRange(location: 4, length: 3), "`<u>` is one dimmed mark")
        XCTAssertEqual(span?.close, NSRange(location: 14, length: 4), "`</u>` is the other")
        XCTAssertEqual(span?.inner, NSRange(location: 7, length: 7))
    }

    func testBoldIsNeverAlsoReadAsItalicAndBulletsAreNotItalic() {
        XCTAssertEqual(BodyFormat.spans(in: "**52 was a squeeze**").map(\.mark), [.bold])
        XCTAssertEqual(BodyFormat.spans(in: "* a bullet\n* another").count, 0, "a `* ` bullet opens nothing")
        XCTAssertEqual(BodyFormat.spans(in: "2 * 3 * 4").count, 0, "spaced stars are arithmetic, not italic")
    }

    func testAMarkPairNeverSpansTwoLines() {
        XCTAssertEqual(BodyFormat.spans(in: "**open\nclose**").count, 0)
    }

    // MARK: - B I U S on a selection

    func testBoldWrapsTheSelectionAndKeepsItSelected() throws {
        let text = "Ask Rui whether the old spindle fits."
        let sel = (text as NSString).range(of: "spindle")
        let edit = try XCTUnwrap(BodyFormat.toggle(.bold, in: text, selection: sel))
        let out = apply(edit, to: text)
        XCTAssertEqual(out, "Ask Rui whether the old **spindle** fits.")
        XCTAssertEqual((out as NSString).substring(with: edit.selection), "spindle", "the word stays selected")
    }

    func testEachMarkWritesItsOwnMarkdown() throws {
        let text = "the spindle"
        let sel = NSRange(location: 4, length: 7)
        XCTAssertEqual(apply(try XCTUnwrap(BodyFormat.toggle(.italic, in: text, selection: sel)), to: text), "the *spindle*")
        XCTAssertEqual(apply(try XCTUnwrap(BodyFormat.toggle(.underline, in: text, selection: sel)), to: text), "the <u>spindle</u>")
        XCTAssertEqual(apply(try XCTUnwrap(BodyFormat.toggle(.strike, in: text, selection: sel)), to: text), "the ~~spindle~~")
    }

    func testTogglingAgainRemovesTheMarks() throws {
        let text = "the **spindle** fits"
        let sel = (text as NSString).range(of: "spindle")
        let edit = try XCTUnwrap(BodyFormat.toggle(.bold, in: text, selection: sel))
        let out = apply(edit, to: text)
        XCTAssertEqual(out, "the spindle fits")
        XCTAssertEqual((out as NSString).substring(with: edit.selection), "spindle")
    }

    func testASelectionThatIncludesTheMarksAlsoUnwraps() throws {
        let text = "the ~~52~~ mount"
        let sel = (text as NSString).range(of: "~~52~~")
        XCTAssertEqual(apply(try XCTUnwrap(BodyFormat.toggle(.strike, in: text, selection: sel)), to: text), "the 52 mount")
    }

    func testMarksHugTheWordsNotTheSurroundingSpaces() throws {
        let text = "the spindle fits"
        let sel = NSRange(location: 3, length: 9)          // " spindle "
        XCTAssertEqual(apply(try XCTUnwrap(BodyFormat.toggle(.bold, in: text, selection: sel)), to: text), "the **spindle** fits")
    }

    func testACaretInsideAWordFormatsThatWord() throws {
        let text = "the spindle fits"
        let edit = try XCTUnwrap(BodyFormat.toggle(.italic, in: text, selection: NSRange(location: 6, length: 0)))
        XCTAssertEqual(apply(edit, to: text), "the *spindle* fits")
    }

    func testAMultiLineSelectionWrapsEachLine() throws {
        let text = "one two\nthree"
        let edit = try XCTUnwrap(BodyFormat.toggle(.bold, in: text, selection: NSRange(location: 0, length: 13)))
        XCTAssertEqual(apply(edit, to: text), "**one two**\n**three**")
    }

    // MARK: - Aa: the caret's line (Title / Heading / Body / lists)

    func testTitleHeadingAndBodyRewriteOnlyTheLinePrefix() {
        let text = "intro\n## Before drilling\nafter"
        let caret = (text as NSString).range(of: "drilling").location
        XCTAssertEqual(apply(BodyFormat.setLineStyle(.title, in: text, caret: caret), to: text),
                       "intro\n# Before drilling\nafter")
        XCTAssertEqual(apply(BodyFormat.setLineStyle(.body, in: text, caret: caret), to: text),
                       "intro\nBefore drilling\nafter")
        XCTAssertEqual(BodyFormat.lineStyle(in: text, caret: caret), .heading)
    }

    func testTheCaretStaysOnTheSameWordAfterAPrefixChange() {
        let text = "Before drilling"
        let caret = 7                                     // before "drilling"
        let edit = BodyFormat.setLineStyle(.heading, in: text, caret: caret)
        let out = apply(edit, to: text)
        XCTAssertEqual(out, "## Before drilling")
        XCTAssertEqual(edit.selection, NSRange(location: 10, length: 0))
    }

    func testListsToggleOffWhenPickedAgainAndNumberFromTheLineAbove() {
        XCTAssertEqual(apply(BodyFormat.setLineStyle(.bullet, in: "item", caret: 2), to: "item"), "- item")
        XCTAssertEqual(apply(BodyFormat.setLineStyle(.bullet, in: "- item", caret: 4), to: "- item"), "item")
        let two = "1. first\nsecond"
        XCTAssertEqual(apply(BodyFormat.setLineStyle(.numbered, in: two, caret: 12), to: two), "1. first\n2. second")
        XCTAssertEqual(apply(BodyFormat.setLineStyle(.checklist, in: "task", caret: 0), to: "task"), "- [ ] task")
        XCTAssertEqual(BodyFormat.lineStyle(in: "- [x] done", caret: 8), .checklist)
    }

    func testAListLineBecomingAHeadingDropsItsListPrefix() {
        XCTAssertEqual(apply(BodyFormat.setLineStyle(.title, in: "- item", caret: 3), to: "- item"), "# item")
    }

    // MARK: - the Mac's commands: Format menu, Aa popover, right-click block

    func testFormatShortcutsAreTheSignedOnesAndClashWithNoAppShortcut() {
        let table = Dictionary(uniqueKeysWithValues: MacEditorFormatting.Command.allCases.map { ($0, $0.chord.glyphs) })
        XCTAssertEqual(table[.bold], "⌘B")
        XCTAssertEqual(table[.italic], "⌘I")
        XCTAssertEqual(table[.underline], "⌘U")
        XCTAssertEqual(table[.strikethrough], "⇧⌘X")
        XCTAssertEqual(table[.title], "⇧⌘T")
        XCTAssertEqual(table[.heading], "⇧⌘H")
        XCTAssertEqual(table[.body], "⇧⌘B")
        XCTAssertEqual(table[.checklist], "⇧⌘L", "Q126's checklist chord stays")
        let chords = MacEditorFormatting.Command.allCases.map(\.chord)
        XCTAssertEqual(Set(chords).count, chords.count, "no chord twice inside Format")
        XCTAssertTrue(Set(chords).isDisjoint(with: Set(AppShortcuts.mac)), "no Format chord steals an app chord")
    }

    func testRightClickFormatBlockEndsWithNewPersonAfterTheFormattingItems() {
        let withPerson = MacEditorFormatting.contextBlock(newPerson: "spindle")
        XCTAssertEqual(withPerson, [.header, .command(.bold), .command(.italic), .command(.underline),
                                    .command(.strikethrough), .newPerson("spindle")],
                       "D196: New person… goes at the right end, after B I U S")
        let without = MacEditorFormatting.contextBlock(newPerson: nil)
        XCTAssertFalse(without.contains { if case .newPerson = $0 { return true } else { return false } })
        XCTAssertEqual(without.first, .header)
    }

    func testAaPopoverActsOnTheLineThenTheSelection() {
        XCTAssertEqual(MacEditorFormatting.popoverStyles, [.title, .heading, .body])
        XCTAssertEqual(MacEditorFormatting.popoverMarks, [.bold, .italic, .underline, .strikethrough])
        XCTAssertEqual(MacEditorFormatting.popoverLists, [.bulletList, .numberedList, .checklist])
    }

    // MARK: - Export confirmation carries Include audio (D196)

    func testExportAsksAboutAudioOnlyWhenTheNoteHasAudio() {
        XCTAssertTrue(MacExportConfirm.asksAboutAudio(hasAudio: true))
        XCTAssertFalse(MacExportConfirm.asksAboutAudio(hasAudio: false))
    }

    func testTheConfirmationRemembersThePerNoteChoice() {
        var include = true
        let changed = MacExportConfirm.apply(includeAudio: false, to: &include)
        XCTAssertFalse(include, "the choice is written to the note (Memo.includeAudioInExport via the row)")
        XCTAssertTrue(changed, "a changed choice is pushed to the phone")
        XCTAssertFalse(MacExportConfirm.apply(includeAudio: false, to: &include), "the same choice writes nothing")
    }

    // MARK: - D112: a photo block moved between paragraphs

    func testAPhotoMovedDownLandsBetweenParagraphsAsItsOwnParagraph() {
        let text = "one\n\n[[img_001]]\n\ntwo\n\nthree"
        let out = BodyFormat.movePhotoBlock(number: 1, toParagraph: 2, in: text)
        XCTAssertEqual(out, "one\n\ntwo\n\n[[img_001]]\n\nthree")
    }

    func testAPhotoMovedToTheTopAndBackKeepsEveryOtherParagraph() {
        let text = "one\n\ntwo\n\n[[img_002]]"
        let up = BodyFormat.movePhotoBlock(number: 2, toParagraph: 0, in: text)
        XCTAssertEqual(up, "[[img_002]]\n\none\n\ntwo")
        XCTAssertEqual(BodyFormat.movePhotoBlock(number: 2, toParagraph: 3, in: up ?? ""), text)
        XCTAssertNil(BodyFormat.movePhotoBlock(number: 9, toParagraph: 0, in: text), "no such photo, no edit")
    }

    // MARK: -

    private func apply(_ edit: BodyFormat.Edit, to text: String) -> String {
        (text as NSString).replacingCharacters(in: edit.range, with: edit.replacement)
    }
}
