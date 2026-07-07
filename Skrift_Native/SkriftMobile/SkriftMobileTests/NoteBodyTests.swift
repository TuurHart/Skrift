import UIKit
import XCTest
@testable import SkriftMobile

/// Tests for the re-founded note body (NoteBodyView): the marker round-trip and
/// debounced write-back, caret carry across external rebuilds, the mode
/// precedence the old TranscriptBodyView swap-tested, and the karaoke word map.
final class NoteBodyTests: XCTestCase {

    @MainActor
    private func makeEditor(transcript: String) -> (NoteBodyView.Coordinator, NoteBodyTextView) {
        let memo = Memo(audioFilename: "memo_edit.m4a", transcript: transcript)
        let coordinator = NoteBodyView.Coordinator(memo: memo, onCommit: {})
        let tv = NoteBodyTextView()
        tv.installAccessoryHosts()
        coordinator.textView = tv
        coordinator.load(force: true)
        return (coordinator, tv)
    }

    // MARK: external rebuilds carry the caret

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

    // MARK: debounced write-back

    @MainActor
    func testCommitDraftWritesBackAndFlagsUserEdited() {
        let (coordinator, tv) = makeEditor(transcript: "hello world")
        tv.attributedText = NSAttributedString(string: "hello brave world")
        coordinator.textViewDidChange(tv)          // marks the draft dirty + schedules
        XCTAssertEqual(coordinator.memo.transcript, "hello world",
                       "the draft must NOT hit the model per keystroke")
        coordinator.commitDraft()                  // debounce fired / end-editing
        XCTAssertEqual(coordinator.memo.transcript, "hello brave world")
        XCTAssertTrue(coordinator.memo.transcriptUserEdited)
        XCTAssertEqual(coordinator.memo.transcriptStatus, .done)
    }

    @MainActor
    func testCommitDraftIsNoOpWhenClean() {
        let (coordinator, _) = makeEditor(transcript: "hello world")
        coordinator.memo.transcriptUserEdited = false
        coordinator.commitDraft()                  // nothing typed
        XCTAssertFalse(coordinator.memo.transcriptUserEdited)
        XCTAssertEqual(coordinator.memo.transcript, "hello world")
    }

    @MainActor
    func testClearingBodyCommitsNilTranscript() {
        let (coordinator, tv) = makeEditor(transcript: "hello world")
        tv.attributedText = NSAttributedString(string: "   ")
        coordinator.textViewDidChange(tv)
        coordinator.commitDraft()
        XCTAssertNil(coordinator.memo.transcript)
    }

    // MARK: quote-protected captures

    @MainActor
    func testCaptureCommitReprependsQuoteVerbatim() {
        let c1 = "> To live is to suffer.\n\nMy ramble about it."
        var meta = MemoMetadata()
        meta.bookTitle = "A Book"
        meta.bookAuthor = "Somebody"
        let memo = Memo.make(transcript: c1, metadata: meta)   // captureQuote is C2-gated
        XCTAssertNotNil(memo.captureQuote, "fixture must parse as a capture")
        let coordinator = NoteBodyView.Coordinator(memo: memo, onCommit: {})
        let tv = NoteBodyTextView()
        tv.installAccessoryHosts()
        coordinator.textView = tv
        coordinator.load(force: true)
        XCTAssertFalse(tv.text.contains(">"), "editor must hold only the ramble")

        tv.attributedText = NSAttributedString(string: "My EDITED ramble.")
        coordinator.textViewDidChange(tv)
        coordinator.commitDraft()
        XCTAssertTrue(coordinator.memo.transcript?.hasPrefix("> To live is to suffer.") == true,
                      "the stored quote block must be untouchable")
        XCTAssertTrue(coordinator.memo.transcript?.contains("My EDITED ramble.") == true)
    }

    // MARK: marker round-trip

    @MainActor
    func testImageMarkersRoundTripThroughAttributedText() {
        let (coordinator, tv) = makeEditor(transcript: "before [[img_001]] after")
        XCTAssertEqual(coordinator.reconstruct(tv.attributedText), "before [[img_001]] after")
    }

    // MARK: mode precedence (ported from the TranscriptBodyView swap)

    func testModePrecedence() {
        XCTAssertEqual(NoteBody.mode(isPlaying: true, status: .transcribing), .playing,
                       "playback wins over the in-flight guard")
        XCTAssertEqual(NoteBody.mode(isPlaying: true, status: .done), .playing)
        XCTAssertEqual(NoteBody.mode(isPlaying: false, status: .transcribing), .reading,
                       "an in-flight transcription is read-only")
        XCTAssertEqual(NoteBody.mode(isPlaying: false, status: .done), .editing)
        XCTAssertEqual(NoteBody.mode(isPlaying: false, status: .failed), .editing)
    }
}

/// The raw⇄display transform (chunk 4 — live checklists join the image markers).
final class BodyTransformTests: XCTestCase {

    func testPiecesSplitTextImagesAndTasks() {
        let raw = "intro [[img_001]]\n- [ ] buy milk\n- [x] done\ntail"
        let pieces = BodyTransform.pieces(of: raw)
        let kinds: [BodyTransform.Segment] = pieces.map(\.segment)
        XCTAssertEqual(kinds, [
            .text("intro "), .image(1), .text("\n"),
            .task(checked: false), .text(" buy milk\n"),
            .task(checked: true), .text(" done\ntail"),
        ])
    }

    func testTaskRequiresLineStart() {
        let pieces = BodyTransform.pieces(of: "mention - [ ] mid-line")
        XCTAssertEqual(pieces.count, 1, "a mid-line '- [ ]' is prose, not a task")
    }

    func testIndentStaysText() {
        let pieces = BodyTransform.pieces(of: "  - [X] indented")
        XCTAssertEqual(pieces.map(\.segment),
                       [.text("  "), .task(checked: true), .text(" indented")])
    }

    func testDisplayRangeAccountsForTasksAndImages() {
        // raw: "- [ ] see [[img_001]] Jack" — span over "Jack" (raw 22..26)
        let raw = "- [ ] see [[img_001]] Jack"
        let jack = (raw as NSString).range(of: "Jack")
        let display = BodyTransform.displayRange(forRaw: jack, in: raw)
        // task "- [ ]" (5→1) saves 4; img (11→1) saves 10 → display loc = 22-14
        XCTAssertEqual(display, NSRange(location: jack.location - 14, length: 4))
    }

    @MainActor
    func testChecklistRoundTripsThroughTheEditor() {
        let raw = "- [ ] buy milk\n- [x] call Jack"
        let memo = Memo(audioFilename: "memo_t.m4a", transcript: raw)
        let coordinator = NoteBodyView.Coordinator(memo: memo, onCommit: {})
        let tv = NoteBodyTextView()
        tv.installAccessoryHosts()
        coordinator.textView = tv
        coordinator.load(force: true)
        XCTAssertEqual(coordinator.reconstruct(tv.attributedText), raw, "byte-exact round trip")
        XCTAssertEqual(tv.text.filter { $0 == "\u{FFFC}" }.count, 2, "both prefixes are checkbox glyphs")
    }

    @MainActor
    func testToggleFlipsTheRawSyntax() {
        let memo = Memo(audioFilename: "memo_t2.m4a", transcript: "- [ ] buy milk")
        let coordinator = NoteBodyView.Coordinator(memo: memo, onCommit: {})
        let tv = NoteBodyTextView()
        tv.installAccessoryHosts()
        coordinator.textView = tv
        coordinator.load(force: true)
        coordinator.toggleTask(at: 0)
        XCTAssertEqual(memo.transcript, "- [x] buy milk")
        XCTAssertTrue(memo.transcriptUserEdited)
        coordinator.toggleTask(at: 0)
        XCTAssertEqual(memo.transcript, "- [ ] buy milk")
    }
}

/// Memo↔memo link syntax + editor round-trip (chunk 5).
final class MemoLinkTests: XCTestCase {

    private let idA = UUID(uuidString: "AAAAAAAA-1111-2222-3333-444444444444")!

    func testLinkBuildsSafeSyntax() {
        XCTAssertEqual(MemoLinkSyntax.link(id: idA, title: "Trip | notes [[x]]"),
                       "[[memo:\(idA.uuidString)|Trip   notes x]]")
        XCTAssertEqual(MemoLinkSyntax.link(id: idA, title: "  "),
                       "[[memo:\(idA.uuidString)|Untitled]]")
    }

    func testOccurrencesAndTargets() {
        let text = "See [[memo:\(idA.uuidString)|Harbor]] and plain [[Hotel]]."
        let occs = MemoLinkSyntax.occurrences(in: text)
        XCTAssertEqual(occs.count, 1)
        XCTAssertEqual(occs.first?.id, idA)
        XCTAssertEqual(occs.first?.title, "Harbor")
        XCTAssertEqual(MemoLinkSyntax.targets(in: text), [idA])
    }

    func testExportRewriteFallbackAndPrecise() {
        let text = "See [[memo:\(idA.uuidString)|Harbor]]."
        XCTAssertEqual(MemoLinkSyntax.exportRewrite(text), "See [[Harbor]].")
        XCTAssertEqual(MemoLinkSyntax.exportRewrite(text, resolveStem: { _ in "Harbor walk-AAAAAAAA" }),
                       "See [[Harbor walk-AAAAAAAA|Harbor]].")
        XCTAssertEqual(MemoLinkSyntax.exportRewrite("no links"), "no links")
    }

    func testCompilerEmitsWikilinkNotRawSyntax() {
        let input = CompilerInput(filename: "m.m4a",
                                  transcript: "Body with [[memo:\(idA.uuidString)|Harbor]].",
                                  enhancedTitle: "T")
        let md = Compiler.compile(input, author: "A")
        XCTAssertFalse(md.contains("[[memo:"), "raw memo-link syntax must never reach the vault")
        XCTAssertTrue(md.contains("[[Harbor]]"))
    }

    @MainActor
    func testMemoLinkRoundTripsThroughTheEditor() {
        let raw = "Start [[memo:\(idA.uuidString)|Harbor]] end"
        let memo = Memo(audioFilename: "memo_l.m4a", transcript: raw)
        let coordinator = NoteBodyView.Coordinator(memo: memo, onCommit: {})
        let tv = NoteBodyTextView()
        tv.installAccessoryHosts()
        coordinator.textView = tv
        coordinator.load(force: true)
        XCTAssertEqual(tv.text.filter { $0 == "\u{FFFC}" }.count, 1, "the link renders as one chip")
        XCTAssertEqual(coordinator.reconstruct(tv.attributedText), raw, "byte-exact round trip")
    }

    func testEscrowStripsAndReattachRestores() {
        let raw = "See [[memo:\(idA.uuidString)|Harbor walk]] for detail."
        let (stripped, links) = MemoLinkSyntax.escrowForEditing(raw)
        XCTAssertEqual(stripped, "See Harbor walk for detail.", "the LLM reads natural prose")
        XCTAssertEqual(links.count, 1)
        // A benign copy-edit that recases the title still reattaches (surface kept).
        let edited = "See harbor walk for the detail."
        XCTAssertEqual(MemoLinkSyntax.reattach(edited: edited, links: links),
                       "See [[memo:\(idA.uuidString)|harbor walk]] for the detail.")
    }

    func testReattachFailsWhenTheTitleWasEditedAway() {
        let raw = "See [[memo:\(idA.uuidString)|Harbor walk]]."
        let (_, links) = MemoLinkSyntax.escrowForEditing(raw)
        XCTAssertNil(MemoLinkSyntax.reattach(edited: "See the waterfront stroll.", links: links),
                     "a lost title must force the caller's fallback to the unedited body")
    }

    func testSanitiserNeverLinksInsideALinkTitle() {
        // "Hendri" is a distinctive, auto-linkable name — but INSIDE a memo-link
        // title it must stay untouched (nested [[…]] would corrupt the syntax).
        let hendri = Person(canonical: "[[Hendri van Niekerk]]",
                            aliases: ["Hendri van Niekerk", "Hendri"], short: "Hendri",
                            lastModifiedAt: "2026-07-07T00:00:00.000Z")
        let raw = "Talked to Hendri about [[memo:\(idA.uuidString)|Lunch with Hendri]]."
        let out = Sanitiser.process(text: raw, people: [hendri]).sanitised
        XCTAssertTrue(out.contains("[[memo:\(idA.uuidString)|Lunch with Hendri]]"),
                      "the link title must survive byte-exact — got: \(out)")
        XCTAssertTrue(out.contains("[[Hendri van Niekerk"),
                      "the prose mention outside the link still auto-links — got: \(out)")
    }

    @MainActor
    func testInsertMemoLinkReplacesTheTypedTrigger() {
        let memo = Memo(audioFilename: "memo_l2.m4a", transcript: "Hello ")
        let coordinator = NoteBodyView.Coordinator(memo: memo, onCommit: {})
        let tv = NoteBodyTextView()
        tv.installAccessoryHosts()
        coordinator.textView = tv
        coordinator.load(force: true)
        // Simulate typing "[[" at the end (the trigger the picker replaces).
        tv.textStorage.append(NSAttributedString(string: "[["))
        tv.selectedRange = NSRange(location: tv.textStorage.length, length: 0)
        coordinator.textViewDidChange(tv)      // detects the trigger
        coordinator.insertMemoLink(id: idA, title: "Harbor")
        XCTAssertEqual(memo.transcript, "Hello [[memo:\(idA.uuidString)|Harbor]] ")
    }
}

/// Share-out + stats helpers (chunk 2 survey folds).
final class MemoShareTests: XCTestCase {

    func testMarkdownComposesTitleAndStripsMarkers() {
        let md = MemoShare.markdown(title: "Evening walk",
                                    body: "First line. [[img_001]] Second line.")
        XCTAssertEqual(md, "# Evening walk\n\nFirst line.  Second line.")
        XCTAssertFalse(md.contains("[[img"))
    }

    func testMarkdownWithoutTitleIsJustTheBody() {
        XCTAssertEqual(MemoShare.markdown(title: "  ", body: "Body."), "Body.")
        XCTAssertEqual(MemoShare.markdown(title: nil, body: "Body."), "Body.")
    }

    func testMarkdownCollapsesMarkerOnlyParagraphs() {
        let md = MemoShare.markdown(title: nil, body: "Before.\n\n[[img_001]]\n\nAfter.")
        XCTAssertEqual(md, "Before.\n\n\nAfter.".replacingOccurrences(of: "\n\n\n", with: "\n\n"))
    }

    func testWordCountSkipsMarkers() {
        XCTAssertEqual(MemoShare.wordCount(of: "one two [[img_001]] three"), 3)
        XCTAssertEqual(MemoShare.wordCount(of: nil), 0)
        XCTAssertEqual(MemoShare.wordCount(of: "  "), 0)
    }
}

/// The karaoke word map: display-text word ranges must align with the timings
/// sidecar's word indexing (whitespace-delimited spoken words; attachment glyphs
/// are not words).
final class KaraokeMapTests: XCTestCase {

    func testPlainWords() {
        let ranges = KaraokeMap.wordRanges(in: "one two  three" as NSString)
        XCTAssertEqual(ranges.count, 3)
        XCTAssertEqual(ranges[0], NSRange(location: 0, length: 3))
        XCTAssertEqual(ranges[1], NSRange(location: 4, length: 3))
        XCTAssertEqual(ranges[2], NSRange(location: 9, length: 5))
    }

    func testNewlinesSplitWords() {
        let ranges = KaraokeMap.wordRanges(in: "alpha\nbeta\n\ngamma" as NSString)
        XCTAssertEqual(ranges.count, 3)
    }

    func testAttachmentGlyphIsNotAWord() {
        let text = "before \u{FFFC} after" as NSString
        let ranges = KaraokeMap.wordRanges(in: text)
        XCTAssertEqual(ranges.count, 2)
        XCTAssertEqual(text.substring(with: ranges[1]), "after")
    }

    func testAttachmentGluedToWordCountsOnce() {
        let text = "word\u{FFFC} next" as NSString
        let ranges = KaraokeMap.wordRanges(in: text)
        XCTAssertEqual(ranges.count, 2, "a glued attachment must not add a word")
    }

    func testWordIndexAtCharIndex() {
        let ranges = KaraokeMap.wordRanges(in: "one two three" as NSString)
        XCTAssertEqual(KaraokeMap.wordIndex(at: 0, in: ranges), 0)
        XCTAssertEqual(KaraokeMap.wordIndex(at: 5, in: ranges), 1)
        XCTAssertEqual(KaraokeMap.wordIndex(at: 3, in: ranges), 0, "whitespace maps to the word just read")
        XCTAssertEqual(KaraokeMap.wordIndex(at: 12, in: ranges), 2)
        XCTAssertNil(KaraokeMap.wordIndex(at: 0, in: []))
    }
}
