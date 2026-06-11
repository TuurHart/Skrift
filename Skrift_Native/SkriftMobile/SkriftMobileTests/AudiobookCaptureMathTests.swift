import XCTest
@testable import SkriftMobile

/// Pure capture math: span proposal/window clamping, sentence-snap-outward,
/// and the C1 blockquote formatting.
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

    // MARK: - Micro-scrubber window clamping

    func testWindowAroundMidFile() {
        let w = CaptureSpan.window(now: 756, duration: 3600)
        XCTAssertEqual(w.start, 696)
        XCTAssertEqual(w.end, 771)
    }

    func testWindowClampsAtFileStart() {
        let w = CaptureSpan.window(now: 20, duration: 3600)
        XCTAssertEqual(w.start, 0)
        XCTAssertEqual(w.end, 35)
    }

    func testWindowClampsAtFileEnd() {
        let w = CaptureSpan.window(now: 3595, duration: 3600)
        XCTAssertEqual(w.start, 3535)
        XCTAssertEqual(w.end, 3600)
    }

    func testWindowContainsProposal() {
        for now in [0.0, 5, 31, 800, 3599] {
            let span = CaptureSpan.proposal(now: now, duration: 3600)
            let w = CaptureSpan.window(now: now, duration: 3600)
            XCTAssertLessThanOrEqual(w.start, span.start, "window must contain the proposal (now=\(now))")
            XCTAssertGreaterThanOrEqual(w.end, span.end, "window must contain the proposal (now=\(now))")
        }
    }

    func testTranscriptionBufferPadsAndClamps() {
        let buffer = CaptureSpan.transcriptionBuffer(
            for: .init(start: 10, end: 40), duration: 50
        )
        XCTAssertEqual(buffer.start, 0)    // 10 − 20 clamps to 0
        XCTAssertEqual(buffer.end, 50)     // 40 + 20 clamps to duration
    }

    // MARK: - Sentence snap (outward on both edges)

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
            WordTiming(word: "“Optimism", start: 0, end: 0.4),
            WordTiming(word: "wins.”", start: 0.5, end: 0.9),
            WordTiming(word: "He", start: 1.0, end: 1.2),
            WordTiming(word: "smiled.", start: 1.3, end: 1.7),
        ]
        // wins.” must count as a sentence end despite the trailing quote.
        let snapped = SentenceSnap.snap(words: quoted, proposedIn: 0.1, proposedOut: 0.6)
        XCTAssertEqual(snapped?.end, 0.9)
        XCTAssertEqual(snapped?.text, "“Optimism wins.”")
    }

    func testSnapEmptyWordsReturnsNil() {
        XCTAssertNil(SentenceSnap.snap(words: [], proposedIn: 0, proposedOut: 5))
    }

    func testIsSentenceEnd() {
        XCTAssertTrue(SentenceSnap.isSentenceEnd("done."))
        XCTAssertTrue(SentenceSnap.isSentenceEnd("what?!"))
        XCTAssertTrue(SentenceSnap.isSentenceEnd("wait…"))
        XCTAssertTrue(SentenceSnap.isSentenceEnd("said.”"))
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
            "only the LEADING block is the quote — later ‘>’ lines are ramble content"
        )
    }
}
