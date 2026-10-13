import XCTest
@testable import SkriftMobile

/// Q359 (D115, D112, signed mock Q350-note-editor-apple): every toolbar action of the phone
/// editor writes the right Markdown, and moving a photo keeps every marker exactly once in the
/// order the user left them. The editor runs these same `BodyFormat` rules on its text storage.
final class EditorFormattingTests: XCTestCase {

    private func apply(_ r: BodyFormat.Result) -> String { r.text }

    // MARK: selection bar + Aa: B I U S

    func testBoldWrapsTheSelectionInDoubleStars() {
        let text = "Ask Rui about the spindle mount."
        let sel = (text as NSString).range(of: "spindle")
        let r = BodyFormat.toggle(.bold, in: text, selection: sel)
        XCTAssertEqual(r.text, "Ask Rui about the **spindle** mount.")
        XCTAssertEqual((r.text as NSString).substring(with: r.selection), "spindle",
                       "the same word stays selected inside the marks")
    }

    func testItalicUnderlineAndStrikeWriteTheirMarks() {
        let text = "the old spindle"
        let sel = (text as NSString).range(of: "old")
        XCTAssertEqual(BodyFormat.toggle(.italic, in: text, selection: sel).text, "the *old* spindle")
        XCTAssertEqual(BodyFormat.toggle(.underline, in: text, selection: sel).text, "the <u>old</u> spindle")
        XCTAssertEqual(BodyFormat.toggle(.strike, in: text, selection: sel).text, "the ~~old~~ spindle")
    }

    func testTogglingAgainRemovesTheMarks() {
        for mark in BodyFormat.InlineMark.allCases {
            let text = "the old spindle"
            let sel = (text as NSString).range(of: "old")
            let on = BodyFormat.toggle(mark, in: text, selection: sel)
            let off = BodyFormat.toggle(mark, in: on.text, selection: on.selection)
            XCTAssertEqual(off.text, text, "\(mark) toggles back off")
            XCTAssertEqual((off.text as NSString).substring(with: off.selection), "old")
        }
    }

    func testASelectionThatIncludesTheMarksAlsoUnwraps() {
        let text = "a **52** mount"
        let sel = (text as NSString).range(of: "**52**")
        XCTAssertEqual(BodyFormat.toggle(.bold, in: text, selection: sel).text, "a 52 mount")
    }

    func testItalicInsideBoldIsNotMistakenForBold() {
        let text = "a **52** mount"
        let sel = (text as NSString).range(of: "52")
        XCTAssertEqual(BodyFormat.toggle(.italic, in: text, selection: sel).text, "a ***52*** mount")
        XCTAssertEqual(BodyFormat.isActive(.italic, in: text, selection: sel), false)
        XCTAssertEqual(BodyFormat.isActive(.bold, in: text, selection: sel), true)
    }

    func testAnEmptySelectionInsertsAnEmptyPairWithTheCaretInside() {
        let text = "ab"
        let r = BodyFormat.toggle(.bold, in: text, selection: NSRange(location: 1, length: 0))
        XCTAssertEqual(r.text, "a****b")
        XCTAssertEqual(r.selection, NSRange(location: 3, length: 0))
    }

    func testTrailingSpaceInTheSelectionStaysOutsideTheMarks() {
        let text = "old spindle"
        let r = BodyFormat.toggle(.bold, in: text, selection: NSRange(location: 0, length: 4))
        XCTAssertEqual(r.text, "**old** spindle", "Obsidian only renders a pair with no inner edge space")
    }

    // MARK: the dim-visible marks (C24/C116): underline is a mark pair too

    func testUnderlineTagsAreAMarkPairForDimming() {
        let text = "keep <u>this</u> and **that**, *one*, ~~gone~~"
        let spans = BodyFormat.inlineMarks(in: text)
        let ns = text as NSString
        let byMark = Dictionary(grouping: spans, by: \.mark)
        XCTAssertEqual(byMark[.underline]?.count, 1)
        let u = byMark[.underline]![0]
        XCTAssertEqual(ns.substring(with: u.open), "<u>")
        XCTAssertEqual(ns.substring(with: u.content), "this")
        XCTAssertEqual(ns.substring(with: u.close), "</u>")
        XCTAssertEqual(byMark[.bold].map { $0.map { ns.substring(with: $0.content) } }, ["that"])
        XCTAssertEqual(byMark[.italic].map { $0.map { ns.substring(with: $0.content) } }, ["one"])
        XCTAssertEqual(byMark[.strike].map { $0.map { ns.substring(with: $0.content) } }, ["gone"])
    }

    func testAStrayStarIsNotAMark() {
        XCTAssertTrue(BodyFormat.inlineMarks(in: "5 * 3 = 15 and 2 * 4").isEmpty)
        XCTAssertTrue(BodyFormat.inlineMarks(in: "a lone <u> tag").isEmpty)
    }

    // MARK: Aa: Title, Heading, Body, lists — act on the caret's line

    func testTitleHeadingAndBodyRestyleTheCaretLine() {
        let text = "first line\nBefore drilling\nlast"
        let caret = NSRange(location: (text as NSString).range(of: "drilling").location, length: 0)
        XCTAssertEqual(BodyFormat.setStyle(.title, in: text, selection: caret).text,
                       "first line\n# Before drilling\nlast")
        let heading = BodyFormat.setStyle(.heading, in: text, selection: caret)
        XCTAssertEqual(heading.text, "first line\n## Before drilling\nlast")
        let body = BodyFormat.setStyle(.body, in: heading.text, selection: heading.selection)
        XCTAssertEqual(body.text, text)
        XCTAssertEqual(BodyFormat.lineStyle(at: heading.selection.location, in: heading.text), .heading)
    }

    func testListsWriteTheirMarkdownAndToggleOff() {
        let text = "Print a test ring"
        let caret = NSRange(location: 3, length: 0)
        let bullet = BodyFormat.setStyle(.bullet, in: text, selection: caret)
        XCTAssertEqual(bullet.text, "- Print a test ring")
        XCTAssertEqual(BodyFormat.setStyle(.numbered, in: text, selection: caret).text, "1. Print a test ring")
        let check = BodyFormat.setStyle(.checklist, in: text, selection: caret)
        XCTAssertEqual(check.text, "- [ ] Print a test ring")
        XCTAssertEqual(BodyFormat.setStyle(.checklist, in: check.text, selection: check.selection).text, text,
                       "the same list again turns it back into body text")
        XCTAssertEqual(BodyFormat.setStyle(.bullet, in: check.text, selection: check.selection).text,
                       "- Print a test ring", "a list switches kind without stacking prefixes")
    }

    func testNumberedContinuesThePreviousNumber() {
        let text = "1. one\n2. two\nthree"
        let caret = NSRange(location: (text as NSString).range(of: "three").location, length: 0)
        XCTAssertEqual(BodyFormat.setStyle(.numbered, in: text, selection: caret).text, "1. one\n2. two\n3. three")
    }

    func testTheCaretKeepsItsPlaceInTheWordsAfterARestyle() {
        let text = "Before drilling"
        let caret = NSRange(location: 7, length: 0)             // "Before |drilling"
        let r = BodyFormat.setStyle(.heading, in: text, selection: caret)
        XCTAssertEqual(r.selection.location, 10)
        XCTAssertEqual((r.text as NSString).substring(from: r.selection.location), "drilling")
    }

    func testCheckedTasksReadAsChecklist() {
        XCTAssertEqual(BodyFormat.lineStyle(at: 2, in: "- [x] done"), .checklist)
        XCTAssertEqual(BodyFormat.lineStyle(at: 2, in: "plain"), .body)
        XCTAssertEqual(BodyFormat.lineStyle(at: 2, in: "### deep"), .heading)
    }

    // MARK: D112: move a photo between paragraphs

    func testMovingAPhotoKeepsEveryMarkerOnceInTheNewOrder() {
        let body = "Intro line.\n\n[[img_001]]\n\nMiddle paragraph.\n\n[[img_002]]\n\nLast words."
        let moved = BodyFormat.movePhoto(marker: 2, in: body, toParagraph: 1)
        XCTAssertEqual(moved, "Intro line.\n\n[[img_002]]\n\n[[img_001]]\n\nMiddle paragraph.\n\nLast words.")
        XCTAssertEqual(moved.components(separatedBy: "[[img_001]]").count, 2)
        XCTAssertEqual(moved.components(separatedBy: "[[img_002]]").count, 2)
        // The commit (C10, user edited) keeps the order the user left: it never snaps back.
        let manifest = [ImageManifestEntry(filename: "a.jpg", offsetSeconds: 0),
                        ImageManifestEntry(filename: "b.jpg", offsetSeconds: 0)]
        let stored = BodyV2.committed(BodyV2.Input(text: moved, manifest: manifest,
                                                   source: .typed, userEdited: true))
        XCTAssertEqual(stored, moved)
    }

    func testMovingAPhotoToTheEndAndToTheTop() {
        let body = "One.\n\n[[img_001]]\n\nTwo."
        XCTAssertEqual(BodyFormat.movePhoto(marker: 1, in: body, toParagraph: 99), "One.\n\nTwo.\n\n[[img_001]]")
        XCTAssertEqual(BodyFormat.movePhoto(marker: 1, in: body, toParagraph: 0), "[[img_001]]\n\nOne.\n\nTwo.")
        XCTAssertEqual(BodyFormat.movePhoto(marker: 3, in: body, toParagraph: 0), body, "an absent marker is a no-op")
    }
}
