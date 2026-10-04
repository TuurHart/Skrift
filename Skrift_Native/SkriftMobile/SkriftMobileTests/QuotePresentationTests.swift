import UIKit
import XCTest
@testable import SkriftMobile

/// The styled-quote presentation for audiobook captures (device-test P1):
/// `CaptureQuote` (Models/MemoDisplay.swift) splits the C1 "> " block off the
/// transcript for display + quote-protected editing, and
/// `quoteAttributionLabel` derives the "— Author, Book · ch. N" caption from
/// the C2 metadata. The stored transcript must keep its raw "> " lines — the
/// editor tests prove edits can't corrupt them.
final class QuotePresentationTests: XCTestCase {

    private let c1 = "> Optimism is not the belief that things will go well,\n"
        + "> but a way of explaining failure.\n"
        + "\n"
        + "My take: failure as input, not verdict.\nSecond ramble line."

    // MARK: - CaptureQuote.split

    func testSplitSeparatesQuoteAndRamble() {
        let split = CaptureQuote.split(c1)
        XCTAssertEqual(
            split?.displayText,
            "Optimism is not the belief that things will go well,\nbut a way of explaining failure."
        )
        XCTAssertEqual(split?.ramble, "My take: failure as input, not verdict.\nSecond ramble line.")
        XCTAssertEqual(
            split?.rawBlock,
            "> Optimism is not the belief that things will go well,\n> but a way of explaining failure.\n"
        )
    }

    func testSplitRoundTripsC1ShapesByteExactly() {
        // The shapes the app writes (QuoteFormatting.blockquote + the append
        // flow): quote block, blank line(s), ramble — plus quote-only.
        let transcripts = [
            c1,
            "> Just the quote.",
            "> Just the quote.\n",
            "> Q.\n\n\nDouble-blank separator.",
            ">First.\n>\n> Second.\n\nRamble.",
            "\n> Leading blank tolerated.\n\nRamble.",
        ]
        for t in transcripts {
            guard let split = CaptureQuote.split(t) else {
                XCTFail("expected a quote split for: \(t)"); continue
            }
            XCTAssertEqual(split.body(withRamble: split.ramble), t,
                           "round trip must be byte-exact for: \(t)")
        }
    }

    func testSplitNilWithoutALeadingQuote() {
        XCTAssertNil(CaptureQuote.split(nil))
        XCTAssertNil(CaptureQuote.split(""))
        XCTAssertNil(CaptureQuote.split("Plain transcript."))
        XCTAssertNil(CaptureQuote.split("Ramble first.\n> not a leading quote"))
        XCTAssertNil(CaptureQuote.split(">"), "empty markers alone aren't a quote")
        XCTAssertNil(CaptureQuote.split(">\n>  "))
    }

    func testSplitKeepsBareSpacerMarkersAsParagraphBreaks() {
        let split = CaptureQuote.split(">First.\n>\n> Second.\n\nRamble.")
        XCTAssertEqual(split?.displayText, "First.\n\nSecond.")
        XCTAssertEqual(split?.ramble, "Ramble.")
    }

    // MARK: - Full-text karaoke (playback runs over quote + ramble)

    func testSpokenWordCountIsTheRamblesKaraokeBaseIndex() {
        // The sidecar holds the quote's spoken words from 0, the ramble's after
        // — the playing mode's ramble region starts at spokenWordCount. The ">"
        // markers are NOT words (counting them shifted the old highlight off
        // the timings).
        XCTAssertEqual(CaptureQuote.split("> one two\n> three\n\nramble")?.spokenWordCount, 3)
        XCTAssertEqual(CaptureQuote.split(">First.\n>\n> Second.\n\nR.")?.spokenWordCount, 2)
        XCTAssertEqual(CaptureQuote.split(c1)?.spokenWordCount, 16)
    }

    // (The old KaraokeWordLayout per-line grid test retired with the FlowLayout
    // word grid: the re-founded editor paints the highlight on the text storage
    // in place, so newline structure is native — see KaraokeMapTests.)

    // MARK: - Mode derivation (one place: playback > transcribing > editable)

    func testTranscriptBodyModePrecedence() {
        XCTAssertEqual(NoteBody.mode(isPlaying: true, status: .transcribing), .playing,
                       "playback always wins — full-text karaoke")
        XCTAssertEqual(NoteBody.mode(isPlaying: true, status: .done), .playing)
        XCTAssertEqual(NoteBody.mode(isPlaying: false, status: .transcribing), .reading,
                       "an in-flight append must NOT show an editor (stale-draft clobber)")
        XCTAssertEqual(NoteBody.mode(isPlaying: false, status: .done), .editing)
        XCTAssertEqual(NoteBody.mode(isPlaying: false, status: .failed), .editing)
    }

    // MARK: - Reassembly (the editor's write-back)

    func testTranscriptWithRamblePreservesTheRawBlock() {
        let split = CaptureQuote.split(c1)!
        XCTAssertEqual(
            split.body(withRamble: "Rewritten thoughts."),
            "> Optimism is not the belief that things will go well,\n"
                + "> but a way of explaining failure.\n\nRewritten thoughts."
        )
    }

    func testTranscriptWithEmptyRambleLeavesAQuoteOnlyCapture() {
        let split = CaptureQuote.split(c1)!
        XCTAssertEqual(split.body(withRamble: ""), split.rawBlock)
        XCTAssertEqual(split.body(withRamble: "  \n "), split.rawBlock)
    }

    func testTranscriptWithFirstRambleInsertsTheBlankSeparator() {
        // Quote-only capture (no separator yet) + the first ramble → C1 shape.
        let split = CaptureQuote.split("> Just the quote.")!
        XCTAssertEqual(split.body(withRamble: "First thoughts."),
                       "> Just the quote.\n\nFirst thoughts.")
    }

    func testDegenerateMissingSeparatorNormalisesWithoutTouchingTheBytes() {
        let split = CaptureQuote.split("> Q.\nRamble")!
        XCTAssertEqual(split.rawBlock, "> Q.")
        XCTAssertEqual(split.ramble, "Ramble")
        XCTAssertEqual(split.body(withRamble: split.ramble), "> Q.\n\nRamble")
    }

    // MARK: - Memo accessors (C2 gating + attribution)

    private func captureMemo(
        transcript: String?,
        book: String? = "The Beginning of Infinity",
        author: String? = "David Deutsch",
        chapter: String? = nil
    ) -> Memo {
        var meta = MemoMetadata()
        meta.bookTitle = book
        meta.bookAuthor = author
        meta.bookChapter = chapter
        return Memo.make(transcript: transcript, metadata: meta)
    }

    /// UNGATED 2026-07-27 (was `testCaptureQuoteIsGatedOnTheBookMetadata`). The quote look
    /// now rides on the TEXT, not on the C2 metadata — that blob is synced and can be
    /// missing, and a June-2026 capture reached the Mac without it, so the same note drew as
    /// a styled quote on the phone and a raw `> ` wall on the Mac. Only the ATTRIBUTION
    /// caption still needs the metadata.
    func testCaptureQuoteRidesOnTheTextNotTheMetadata() {
        XCTAssertNotNil(captureMemo(transcript: c1).captureQuote)
        XCTAssertNotNil(Memo(transcript: c1).captureQuote,
                        "a blockquote is a quote whether or not the book metadata survived")
        XCTAssertNil(Memo(transcript: c1).quoteAttributionLabel,
                     "…but with no metadata there is no caption to show")
        XCTAssertNil(captureMemo(transcript: "No quote block.").captureQuote)
        XCTAssertNil(captureMemo(transcript: nil).captureQuote)
    }

    func testQuoteAttributionLabelFormats() {
        XCTAssertEqual(captureMemo(transcript: nil, chapter: "4").quoteAttributionLabel,
                       "— David Deutsch, The Beginning of Infinity · ch. 4")
        XCTAssertEqual(captureMemo(transcript: nil, chapter: "The Spark").quoteAttributionLabel,
                       "— David Deutsch, The Beginning of Infinity · The Spark")
        XCTAssertEqual(captureMemo(transcript: nil).quoteAttributionLabel,
                       "— David Deutsch, The Beginning of Infinity")
        XCTAssertEqual(captureMemo(transcript: nil, author: nil, chapter: "4").quoteAttributionLabel,
                       "— The Beginning of Infinity · ch. 4")
        XCTAssertEqual(captureMemo(transcript: nil, author: "  ").quoteAttributionLabel,
                       "— The Beginning of Infinity", "blank author is omitted")
        XCTAssertNil(Memo().quoteAttributionLabel)
        XCTAssertFalse(captureMemo(transcript: nil, chapter: "4").quoteAttributionLabel!.contains("[["),
                       "attribution is plain text — wikilinks are Mac-export-side")
    }

    // MARK: - Quote-protected editor

    @MainActor
    private func makeEditor(memo: Memo) -> (NoteBodyView.Coordinator, UITextView) {
        let coordinator = NoteBodyView.Coordinator(memo: memo, onCommit: { _ in })
        let tv = NoteBodyTextView()
        tv.installAccessoryHosts()
        coordinator.textView = tv
        coordinator.load(force: true)
        return (coordinator, tv)
    }

    @MainActor
    func testEditorShowsOnlyTheRambleForACapture() {
        let (_, tv) = makeEditor(memo: captureMemo(transcript: c1))
        XCTAssertEqual(tv.text, "My take: failure as input, not verdict.\nSecond ramble line.")
        XCTAssertFalse(tv.text.contains(">"), "the quote block never enters the editor")
    }

    @MainActor
    func testEditorWriteBackKeepsTheQuoteVerbatim() {
        let memo = captureMemo(transcript: c1)
        let (coordinator, tv) = makeEditor(memo: memo)
        tv.attributedText = NSAttributedString(string: "Edited ramble.")
        coordinator.textViewDidChange(tv)
        coordinator.commitDraft()
        XCTAssertEqual(
            memo.transcript,
            "> Optimism is not the belief that things will go well,\n"
                + "> but a way of explaining failure.\n\nEdited ramble."
        )
        XCTAssertTrue(memo.transcriptUserEdited)
        XCTAssertEqual(memo.transcriptStatus, .done)
    }

    @MainActor
    func testClearingTheRambleNeverDeletesTheQuote() {
        let memo = captureMemo(transcript: c1)
        let (coordinator, tv) = makeEditor(memo: memo)
        tv.attributedText = NSAttributedString(string: "")
        coordinator.textViewDidChange(tv)
        coordinator.commitDraft()
        XCTAssertEqual(memo.transcript, CaptureQuote.split(c1)?.rawBlock)
        XCTAssertNotNil(memo.captureQuote, "still a valid quote-only capture")
    }

    @MainActor
    func testTypingTheFirstRambleIntoAQuoteOnlyCapture() {
        let memo = captureMemo(transcript: "> Just the quote.")
        let (coordinator, tv) = makeEditor(memo: memo)
        XCTAssertEqual(tv.text, "", "no ramble yet → empty editor")
        tv.attributedText = NSAttributedString(string: "First thoughts.")
        coordinator.textViewDidChange(tv)
        coordinator.commitDraft()
        XCTAssertEqual(memo.transcript, "> Just the quote.\n\nFirst thoughts.")
    }

    @MainActor
    func testExternalRambleChangeRebuildsTheEditor() {
        // e.g. the ramble-append flow landing while the page is open.
        let memo = captureMemo(transcript: c1)
        let (coordinator, tv) = makeEditor(memo: memo)
        memo.transcript = CaptureQuote.split(c1)!.body(withRamble: "Appended thoughts.")
        coordinator.load(force: false)
        XCTAssertEqual(tv.text, "Appended thoughts.")
    }

    /// The other half of the ungating: a `> ` block is quote-PROTECTED too, metadata or not.
    /// The editor holds only the ramble, so typing can't corrupt the quote — which is the
    /// whole reason the split exists. Was `testNonCaptureMemoIsNotQuoteProtected`.
    @MainActor
    func testQuoteIsProtectedEvenWithoutBookMetadata() {
        let memo = Memo(transcript: "> q\n\nr")
        let (_, tv) = makeEditor(memo: memo)
        XCTAssertEqual(tv.text, "r", "the editor holds the ramble; the quote sits above it")
    }

    /// A body with NO quote still edits whole — the split must not invent a block.
    @MainActor
    func testPlainMemoStillEditsWhole() {
        let memo = Memo(transcript: "just prose\n\nmore prose")
        let (_, tv) = makeEditor(memo: memo)
        XCTAssertEqual(tv.text, "just prose\n\nmore prose")
    }
}
