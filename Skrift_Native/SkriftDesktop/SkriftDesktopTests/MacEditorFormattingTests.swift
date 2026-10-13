import XCTest
import Foundation

/// Q360 (D115, D193, D196, C234; signed mock `mocks/Q350-note-editor-apple.html`; Tuur
/// 2026-10-13 "Apple's full Aa list"): the Mac note editor's formatting. The verbs are the
/// shared `BodyFormat` edits on the stored Markdown (C116), so the editor stays WYSIWYG to the
/// export: Bold `**…**`, Italic `*…*`, Underline `<u>…</u>`, Strikethrough `~~…~~`, Highlight
/// `==…==`, Monostyled `` `…` `` or a fenced block, Title `# `, Heading `## `, Subheading
/// `### `, Bulleted `- `, Dashed `* `, Numbered `1. `, Block Quote `> `.
/// The text view (`BodyTextView`, AppKit) is not compiled into this host-less bundle; it
/// applies exactly these edits, and the full SkriftDesktop build proves the wiring.
final class MacEditorFormattingTests: XCTestCase {

    // MARK: - mark pairs: found, dimmed, styled (C24/C116)

    func testEveryMarkPairIsFoundWithItsTwoMarksAndItsInnerText() {
        let text = "a **bold** b *it* c <u>under</u> d ~~gone~~ e ==lit== f `mono` g"
        let spans = BodyFormat.inlineMarks(in: text)
        let ns = text as NSString
        XCTAssertEqual(spans.map(\.mark), [.bold, .italic, .underline, .strike, .highlight, .code])
        for s in spans {
            XCTAssertEqual(ns.substring(with: s.open), s.mark.open)
            XCTAssertEqual(ns.substring(with: s.close), s.mark.close)
        }
        XCTAssertEqual(spans.map { ns.substring(with: $0.content) }, ["bold", "it", "under", "gone", "lit", "mono"])
    }

    func testUnderlineIsAMarkPairSoBothTagsDim() {
        let span = BodyFormat.inlineMarks(in: "the <u>spindle</u> mount").first
        XCTAssertEqual(span?.mark, .underline)
        XCTAssertEqual(span?.open, NSRange(location: 4, length: 3), "`<u>` is one dimmed mark")
        XCTAssertEqual(span?.close, NSRange(location: 14, length: 4), "`</u>` is the other")
        XCTAssertEqual(span?.content, NSRange(location: 7, length: 7))
    }

    func testBoldIsNeverAlsoReadAsItalicAndDashesAreNotItalic() {
        XCTAssertEqual(BodyFormat.inlineMarks(in: "**52 was a squeeze**").map(\.mark), [.bold])
        XCTAssertEqual(BodyFormat.inlineMarks(in: "* a dash\n* another").count, 0, "a `* ` list opens nothing")
        XCTAssertEqual(BodyFormat.inlineMarks(in: "2 * 3 * 4").count, 0, "spaced stars are arithmetic")
        XCTAssertEqual(BodyFormat.inlineMarks(in: "**open\nclose**").count, 0, "a pair never spans two lines")
    }

    // MARK: - B I U S | highlight on a selection: each writes its markdown, and back

    func testBoldWrapsTheSelectionAndKeepsItSelected() {
        let text = "Ask Rui whether the old spindle fits."
        let r = BodyFormat.toggle(.bold, in: text, selection: (text as NSString).range(of: "spindle"))
        XCTAssertEqual(r.text, "Ask Rui whether the old **spindle** fits.")
        XCTAssertEqual((r.text as NSString).substring(with: r.selection), "spindle", "the word stays selected")
    }

    func testEveryMarkWritesItsMarkdownAndRoundTrips() {
        let expect: [(MacEditorFormatting.Command, String)] = [
            (.bold, "a **word** here"), (.italic, "a *word* here"), (.underline, "a <u>word</u> here"),
            (.strikethrough, "a ~~word~~ here"), (.highlight, "a ==word== here"),
        ]
        for (cmd, md) in expect {
            guard let mark = cmd.mark else { XCTFail("\(cmd.title) has no mark"); continue }
            let on = BodyFormat.toggle(mark, in: "a word here", selection: NSRange(location: 2, length: 4))
            XCTAssertEqual(on.text, md, cmd.title)
            XCTAssertEqual(BodyFormat.inlineMarks(in: on.text).map(\.mark), [mark], "\(cmd.title) dims as a mark pair")
            XCTAssertEqual(BodyFormat.toggle(mark, in: on.text, selection: on.selection).text, "a word here",
                           "\(cmd.title) round-trips")
        }
    }

    func testMarksHugTheWordsNotTheSurroundingSpaces() {
        let r = BodyFormat.toggle(.bold, in: "the spindle fits", selection: NSRange(location: 3, length: 9))
        XCTAssertEqual(r.text, "the **spindle** fits")
    }

    func testASelectionThatIncludesTheMarksAlsoUnwraps() {
        let text = "the ~~52~~ mount"
        XCTAssertEqual(BodyFormat.toggle(.strike, in: text, selection: (text as NSString).range(of: "~~52~~")).text,
                       "the 52 mount")
    }

    // MARK: - Aa: the caret's line, Apple's list

    func testAaListIsApplesOrder() {
        XCTAssertEqual(MacEditorFormatting.popoverMarks, [.bold, .italic, .underline, .strikethrough, .highlight])
        XCTAssertEqual(MacEditorFormatting.popoverStyles, [.title, .heading, .subheading, .body, .monostyled])
        XCTAssertEqual(MacEditorFormatting.popoverLists, [.bulletList, .dashedList, .numberedList])
        XCTAssertEqual(MacEditorFormatting.popoverTail, [.blockQuote])
    }

    func testEveryAaLineItemWritesItsPrefixAndRoundTrips() {
        let expect: [(MacEditorFormatting.Command, String)] = [
            (.title, "# spindle"), (.heading, "## spindle"), (.subheading, "### spindle"), (.body, "spindle"),
            (.bulletList, "- spindle"), (.dashedList, "* spindle"), (.numberedList, "1. spindle"),
            (.blockQuote, "> spindle"),
        ]
        for (cmd, md) in expect {
            guard let style = cmd.lineStyle else { XCTFail("\(cmd.title) has no line style"); continue }
            let on = BodyFormat.setStyle(style, in: "spindle", selection: NSRange(location: 3, length: 0))
            XCTAssertEqual(on.text, md, cmd.title)
            XCTAssertEqual(BodyFormat.lineStyle(at: on.selection.location, in: on.text), style, "\(cmd.title) reads back")
            XCTAssertEqual(BodyFormat.setStyle(.body, in: on.text, selection: on.selection).text, "spindle",
                           "\(cmd.title) → Body round-trips")
        }
    }

    func testTheCaretStaysOnTheSameWordAfterAPrefixChange() {
        let r = BodyFormat.setStyle(.heading, in: "Before drilling", selection: NSRange(location: 7, length: 0))
        XCTAssertEqual(r.text, "## Before drilling")
        XCTAssertEqual(r.selection, NSRange(location: 10, length: 0))
    }

    func testListsAndQuoteTurnOffWhenPickedAgainAndNumbersContinue() {
        for style in [BodyFormat.LineStyle.bullet, .dashed, .numbered, .quote] {
            let on = BodyFormat.setStyle(style, in: "x", selection: NSRange(location: 0, length: 0))
            XCTAssertEqual(BodyFormat.setStyle(style, in: on.text, selection: on.selection).text, "x")
        }
        let two = "1. first\nsecond"
        XCTAssertEqual(BodyFormat.setStyle(.numbered, in: two, selection: NSRange(location: 12, length: 0)).text,
                       "1. first\n2. second")
        XCTAssertEqual(BodyFormat.setStyle(.title, in: "- item", selection: NSRange(location: 3, length: 0)).text,
                       "# item", "a line never stacks two prefixes")
    }

    func testMonostyledIsInlineCodeForASelectionAndAFenceForAParagraph() {
        let text = "one\n\ntwo words\n\nthree"
        XCTAssertEqual(BodyFormat.monostyled(in: text, selection: (text as NSString).range(of: "words")).text,
                       "one\n\ntwo `words`\n\nthree")
        let fenced = BodyFormat.monostyled(in: text, selection: NSRange(location: 6, length: 0))
        XCTAssertEqual(fenced.text, "one\n\n```\ntwo words\n```\n\nthree")
        XCTAssertEqual(BodyFormat.fences(in: fenced.text).count, 1, "both fence lines dim as a pair")
        XCTAssertEqual(BodyFormat.monostyled(in: fenced.text, selection: fenced.selection).text, text,
                       "Monostyled again round-trips")
    }

    func testBodyIsCheckedWhenTheLineIsPlain() {
        XCTAssertEqual(MacEditorFormatting.checkedStyle(.body, inFence: false), .body)
        XCTAssertEqual(MacEditorFormatting.checkedStyle(.bullet, inFence: false), .body)
        XCTAssertEqual(MacEditorFormatting.checkedStyle(.subheading, inFence: false), .subheading)
        XCTAssertEqual(MacEditorFormatting.checkedStyle(.body, inFence: true), .monostyled)
    }

    // MARK: - the Mac's commands: Format menu shortcuts and the right-click block

    func testFormatShortcutsAreApplesAndClashWithNoAppShortcut() {
        let table = Dictionary(uniqueKeysWithValues: MacEditorFormatting.Command.allCases.map { ($0, $0.chord?.glyphs) })
        XCTAssertEqual(table[.bold], "⌘B")
        XCTAssertEqual(table[.italic], "⌘I")
        XCTAssertEqual(table[.underline], "⌘U")
        XCTAssertEqual(table[.strikethrough], "⇧⌘X")
        XCTAssertEqual(table[.title], "⇧⌘T")
        XCTAssertEqual(table[.heading], "⇧⌘H")
        XCTAssertEqual(table[.subheading], "⇧⌘J")
        XCTAssertEqual(table[.body], "⇧⌘B")
        XCTAssertEqual(table[.monostyled], "⇧⌘M")
        XCTAssertEqual(table[.checklist], "⇧⌘L", "Q126's checklist chord stays")
        let chords = MacEditorFormatting.Command.allCases.compactMap(\.chord)
        XCTAssertEqual(Set(chords).count, chords.count, "no chord twice inside Format")
        XCTAssertTrue(Set(chords).isDisjoint(with: Set(AppShortcuts.mac)), "no Format chord steals an app chord")
    }

    func testRightClickFormatBlockEndsWithNewPersonAfterTheFormattingItems() {
        XCTAssertEqual(MacEditorFormatting.contextBlock(newPerson: "spindle"),
                       [.header, .command(.bold), .command(.italic), .command(.underline),
                        .command(.strikethrough), .newPerson("spindle")],
                       "D196: New person… goes at the end, after B I U S")
        let without = MacEditorFormatting.contextBlock(newPerson: nil)
        XCTAssertFalse(without.contains { if case .newPerson = $0 { return true } else { return false } })
        XCTAssertEqual(without.first, .header)
    }

    // MARK: - Export confirmation carries Include audio (D196)

    func testExportAsksAboutAudioOnlyWhenTheNoteHasAudio() {
        XCTAssertTrue(MacExportConfirm.asksAboutAudio(hasAudio: true))
        XCTAssertFalse(MacExportConfirm.asksAboutAudio(hasAudio: false))
    }

    func testTheConfirmationRemembersThePerNoteChoice() {
        var include = true
        XCTAssertTrue(MacExportConfirm.apply(includeAudio: false, to: &include), "a changed choice is pushed to the phone")
        XCTAssertFalse(include, "the choice is written to the note (Memo.includeAudioInExport via the row)")
        XCTAssertFalse(MacExportConfirm.apply(includeAudio: false, to: &include), "the same choice writes nothing")
    }

    // MARK: - D112: a photo block moved between paragraphs

    func testAPhotoMovedDownLandsBetweenParagraphsAsItsOwnParagraph() {
        XCTAssertEqual(BodyFormat.movePhoto(marker: 1, in: "one\n\n[[img_001]]\n\ntwo\n\nthree", toParagraph: 2),
                       "one\n\ntwo\n\n[[img_001]]\n\nthree")
    }

    func testAPhotoMovedToTheTopAndBackKeepsEveryOtherParagraph() {
        let text = "one\n\ntwo\n\n[[img_002]]"
        let up = BodyFormat.movePhoto(marker: 2, in: text, toParagraph: 0)
        XCTAssertEqual(up, "[[img_002]]\n\none\n\ntwo")
        XCTAssertEqual(BodyFormat.movePhoto(marker: 2, in: up, toParagraph: 3), text)
        XCTAssertEqual(BodyFormat.movePhoto(marker: 9, in: text, toParagraph: 0), text, "no such photo, no edit")
    }
}
