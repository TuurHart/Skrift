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
