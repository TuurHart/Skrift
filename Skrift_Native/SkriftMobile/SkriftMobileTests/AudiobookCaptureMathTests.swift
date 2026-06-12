import XCTest
@testable import SkriftMobile

/// Pure capture math: span proposal clamping, sentence-snap-outward, and the
/// C1 blockquote formatting. `CaptureSpan` proposal / `transcriptionBuffer`
/// are unchanged; sentence-snap and formatting are unchanged. Tests that
/// covered the now-retired micro-scrubber window are in `AudiobookScrubberTests`.
final class AudiobookCaptureMathTests: XCTestCase {

    // MARK: - Span proposal clamping

    func testProposalIsLast30Seconds() {
        let span = CaptureSpan.proposal(now: 756, duration: 3600)
        XCTAssertEqual(span.start, 726)
        XCTAssertEqual(span.end, 756)
    }

    func testProposalClampsNearFileStart() {
        let span = CaptureSpan.proposal(now: 10, duration: 3600)
        XCTAssertEqual(span.start, 0)
        XCTAssertEqual(span.end, 10)
    }

    func testProposalAtPositionZeroOffersMinimalForwardSpan() {
        let span = CaptureSpan.proposal(now: 0, duration: 3600)
        XCTAssertEqual(span.start, 0)
        XCTAssertEqual(span.end, CaptureSpan.minimumSpan)
    }

    func testProposalClampsNearFileEnd() {
        // "now" can sit past the duration (player rounding at the very end).
        let span = CaptureSpan.proposal(now: 3605, duration: 3600)
        XCTAssertEqual(span.end, 3600)
        XCTAssertEqual(span.start, 3570)
    }

    func testProposalOnTinyFileStaysInBounds() {
        let span = CaptureSpan.proposal(now: 0.4, duration: 0.5)
        XCTAssertGreaterThanOrEqual(span.start, 0)
        XCTAssertLessThanOrEqual(span.end, 0.5)
        XCTAssertLessThanOrEqual(span.start, span.end)
    }

    // MARK: - Transcription buffer

    func testTranscriptionBufferPadsAndClamps() {
        let buffer = CaptureSpan.transcriptionBuffer(
            for: .init(start: 10, end: 40), duration: 50
        )
        XCTAssertEqual(buffer.start, 0)    // 10 − 20 clamps to 0
        XCTAssertEqual(buffer.end, 50)     // 40 + 20 clamps to duration
    }

    // MARK: - Sentence snap (outward on both edges, unchanged)

    /// "Hello world. Next sentence here. And more." with one word per slot.
    private let words: [WordTiming] = [
        WordTiming(word: "Hello", start: 0.0, end: 0.4),
        WordTiming(word: "world.", start: 0.5, end: 0.9),
        WordTiming(word: "Next", start: 1.0, end: 1.4),
        WordTiming(word: "sentence", start: 1.5, end: 1.9),
        WordTiming(word: "here.", start: 2.0, end: 2.4),
        WordTiming(word: "And", start: 2.5, end: 2.8),
        WordTiming(word: "more.", start: 3.0, end: 3.4),
    ]

    func testSnapMidSentenceMarkersYieldWholeSentence() {
        let snapped = SentenceSnap.snap(words: words, proposedIn: 1.2, proposedOut: 2.1)
        XCTAssertEqual(snapped?.start, 1.0)            // back to "Next"
        XCTAssertEqual(snapped?.end, 2.4)              // forward through "here."
        XCTAssertEqual(snapped?.text, "Next sentence here.")
    }

    func testSnapInMovesEarlierNeverLater() {
        // 0.6 sits inside the FIRST sentence — IN must go back to its start.
        let snapped = SentenceSnap.snap(words: words, proposedIn: 0.6, proposedOut: 2.1)
        XCTAssertEqual(snapped?.start, 0.0)
        XCTAssertEqual(snapped?.text, "Hello world. Next sentence here.")
    }

    func testSnapOutPastLastTerminatorFallsToLastWord() {
        let snapped = SentenceSnap.snap(words: words, proposedIn: 2.6, proposedOut: 10)
        XCTAssertEqual(snapped?.start, 2.5)            // "And"
        XCTAssertEqual(snapped?.end, 3.4)
        XCTAssertEqual(snapped?.text, "And more.")
    }

    func testSnapInBeforeFirstWordUsesFirstSentence() {
        let snapped = SentenceSnap.snap(words: words, proposedIn: -5, proposedOut: 0.7)
        XCTAssertEqual(snapped?.start, 0.0)
        XCTAssertEqual(snapped?.text, "Hello world.")
    }

    func testSnapHandlesTrailingClosingQuotes() {
        let quoted: [WordTiming] = [
            WordTiming(word: "\u{201C}Optimism", start: 0, end: 0.4),
            WordTiming(word: "wins.\u{201D}", start: 0.5, end: 0.9),
            WordTiming(word: "He", start: 1.0, end: 1.2),
            WordTiming(word: "smiled.", start: 1.3, end: 1.7),
        ]
        // wins." must count as a sentence end despite the trailing quote.
        let snapped = SentenceSnap.snap(words: quoted, proposedIn: 0.1, proposedOut: 0.6)
        XCTAssertEqual(snapped?.end, 0.9)
        XCTAssertEqual(snapped?.text, "\u{201C}Optimism wins.\u{201D}")
    }

    func testSnapEmptyWordsReturnsNil() {
        XCTAssertNil(SentenceSnap.snap(words: [], proposedIn: 0, proposedOut: 5))
    }

    func testIsSentenceEnd() {
        XCTAssertTrue(SentenceSnap.isSentenceEnd("done."))
        XCTAssertTrue(SentenceSnap.isSentenceEnd("what?!"))
        XCTAssertTrue(SentenceSnap.isSentenceEnd("wait…"))
        XCTAssertTrue(SentenceSnap.isSentenceEnd("said.\u{201D}"))
        XCTAssertFalse(SentenceSnap.isSentenceEnd("comma,"))
        XCTAssertFalse(SentenceSnap.isSentenceEnd("plain"))
        XCTAssertFalse(SentenceSnap.isSentenceEnd(""))
    }

    // MARK: - C1 blockquote formatting

    func testBlockquoteSingleParagraph() {
        XCTAssertEqual(
            QuoteFormatting.blockquote("Optimism is not the belief that things will go well."),
            "> Optimism is not the belief that things will go well."
        )
    }

    func testBlockquoteMultiLine() {
        XCTAssertEqual(
            QuoteFormatting.blockquote("First line.\n\nSecond line."),
            "> First line.\n>\n> Second line."
        )
    }

    func testBlockquoteEmptyInput() {
        XCTAssertEqual(QuoteFormatting.blockquote("   \n  "), "")
    }

    func testAttributionPreviewHasNoWikilink() {
        let preview = QuoteFormatting.attributionPreview(
            author: "David Deutsch", book: "The Beginning of Infinity", chapter: "4"
        )
        XCTAssertEqual(preview, "— David Deutsch, The Beginning of Infinity, ch. 4")
        XCTAssertFalse(preview.contains("[["), "the phone never writes [[..]] — Mac-side at export only")
    }

    func testAttributionPreviewOmitsMissingPieces() {
        XCTAssertEqual(QuoteFormatting.attributionPreview(author: "A", book: nil, chapter: nil), "— A")
        XCTAssertEqual(QuoteFormatting.attributionPreview(author: nil, book: nil, chapter: nil), "")
    }

    // MARK: - Ramble body (the capture sheet's post-ramble review text)

    func testRambleBodyIsEverythingBelowTheQuoteBlock() {
        let transcript = "> The quote line one,\n> and line two.\n\nMy take on it.\nSecond thought."
        XCTAssertEqual(
            QuoteFormatting.rambleBody(transcript: transcript),
            "My take on it.\nSecond thought."
        )
    }

    func testRambleBodyNilForAQuoteOnlyCapture() {
        XCTAssertNil(QuoteFormatting.rambleBody(transcript: "> Just the quote."))
        XCTAssertNil(QuoteFormatting.rambleBody(transcript: "> Quote.\n>\n> More quote.\n\n  "))
        XCTAssertNil(QuoteFormatting.rambleBody(transcript: ""))
    }

    func testRambleBodyStripsImageMarkersAndKeepsLaterQuoteChars() {
        XCTAssertEqual(
            QuoteFormatting.rambleBody(transcript: "> Q.\n\n[[img_001]] thoughts here\n> spoken aside"),
            "thoughts here\n> spoken aside",
            "only the LEADING block is the quote — later '>' lines are ramble content"
        )
    }

    // MARK: - CaptureMath — mark placement (key cross-checks)

    private let testBounds = CaptureSpan.Span(start: 0, end: 3600)

    func testInMarkBiasIsSevenTenthsOfASecond() {
        XCTAssertEqual(CaptureMath.reactionBias, 0.7,
                       "bias matches the spec and the mock's `−0.7 s` callout")
    }

    func testOutMarkMinimumSpanIsOneSecond() {
        XCTAssertEqual(CaptureMath.minimumSpan, 1)
    }

    func testNudgeDeltaOfOneSecondIsExact() {
        // Verify that a chip tap nudges by EXACTLY 1 s (the spec says ±1s).
        let newIn = CaptureMath.nudgeInMark(current: 100, delta: -1, outMark: 200, bounds: testBounds)
        XCTAssertEqual(newIn, 99)
        let newOut = CaptureMath.nudgeOutMark(current: 200, delta: 1, inMark: 100, bounds: testBounds)
        XCTAssertEqual(newOut, 201)
    }

    func testReplayWindowLookbackMatchesSpec() {
        // Spec says "−45 s" on entry.
        XCTAssertEqual(CaptureSpan.replayLookback, 45,
                       "the initial strip window must look back exactly 45 s")
    }

    func testWindowExtensionStepMatchesSpec() {
        // Spec says ⟲ extends by the same step (45 s).
        XCTAssertEqual(CaptureSpan.windowExtensionStep, 45)
    }
}
