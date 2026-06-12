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

    func testSnapInNearTailForwardSnapsToNextSentence() {
        // 0.6 sits 0.4 s before the next sentence start (1.0). That is within
        // the 1.0 s forward-snap threshold — the reaction-bias overshoot
        // signature — so IN snaps FORWARD to "Next sentence here.".
        let snapped = SentenceSnap.snap(words: words, proposedIn: 0.6, proposedOut: 2.1)
        XCTAssertEqual(snapped?.start, 1.0, "tail of previous sentence: forward snap to next sentence start")
        XCTAssertEqual(snapped?.text, "Next sentence here.")
    }

    func testSnapInDeepInsideSentenceSnapsBackward() {
        // 0.2 sits 0.8 s before the next sentence start (1.0) — within the
        // 1.0 s forward-snap threshold, so it also snaps forward. But a mark
        // EARLY (0.1 s) in a sentence lands 0.9 s before the next start and
        // still forward-snaps. To test genuine backward snap: place the mark
        // far past any nearby sentence boundary (e.g. 1.6 — 0.9 s into the
        // second sentence, 0.9 s before sentence 3 at 2.5). Forward snap:
        // 2.5 − 1.6 = 0.9 s ≤ threshold → snaps FORWARD to sentence 3.
        // For a genuine backward case use proposedIn 1.8 → next start 2.5 is
        // 0.7 s away, still within threshold. Try 1.9 → 2.5 − 1.9 = 0.6 ≤ 1.0.
        // The sentences here are: S0=[0,0.9], S1=[1.0,2.4], S2=[2.5,3.4].
        // Truly mid-sentence backward: place mark so the NEXT sentence is > 1.0 s away.
        // proposedIn=1.4 → next start 2.5, distance 1.1 s > threshold → backward to 1.0.
        let snapped = SentenceSnap.snap(words: words, proposedIn: 1.4, proposedOut: 2.1)
        XCTAssertEqual(snapped?.start, 1.0, "deep mid-sentence: next start > 1.0 s away, snap backward")
        XCTAssertEqual(snapped?.text, "Next sentence here.")
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

    // MARK: - Nearest-boundary IN snap (item 1)
    //
    // Scenario: sentences are "Hello world." (0.0–0.9) and "Next sentence here."
    // (1.0–2.4). The reaction bias of −0.7 s drops the IN mark at 0.9 − 0.7 = 0.2
    // into the TAIL of the first sentence. Nearest-boundary detects the next
    // sentence start (1.0) is only 0.8 s ahead (< 1.0 s threshold) and snaps
    // FORWARD to sentence 2 instead of backward to sentence 1.

    func testSnapInOvershootForwardToNextSentenceStart() {
        // Mark at 0.25 — within 1.0 s before the next sentence start at 1.0.
        // Expected: snaps FORWARD to "Next sentence here." (start = 1.0)
        let snapped = SentenceSnap.snap(words: words, proposedIn: 0.25, proposedOut: 2.1)
        XCTAssertEqual(snapped?.start, 1.0, "overshoot forward: IN should snap to the next sentence start")
        XCTAssertEqual(snapped?.text, "Next sentence here.")
    }

    func testSnapInGenuineMidSentenceSnapsBackward() {
        // Mark at 1.2 — well inside "Next sentence here." (1.0–2.4), not in
        // the forward-snap zone of the following sentence (next start is 2.5,
        // 1.2 to 2.5 = 1.3 s > threshold). Expected: snaps BACKWARD to 1.0.
        let snapped = SentenceSnap.snap(words: words, proposedIn: 1.2, proposedOut: 2.1)
        XCTAssertEqual(snapped?.start, 1.0, "genuine mid-sentence: IN snaps backward (outward)")
        XCTAssertEqual(snapped?.text, "Next sentence here.")
    }

    func testSnapInExactBoundaryStaysAtThatSentenceStart() {
        // Mark exactly at sentence start 1.0 — proposedIn == sentence start.
        // The next sentence start is 2.5, which is 1.5 s away (> threshold).
        // Not in the forward zone. Expected: stays at 1.0 (backward snap to self).
        let snapped = SentenceSnap.snap(words: words, proposedIn: 1.0, proposedOut: 2.1)
        XCTAssertEqual(snapped?.start, 1.0, "exact boundary: lands on the sentence start itself")
    }

    func testSnapInJustBeyondThresholdDoesNotForwardSnap() {
        // Mark at −0.1 — the next sentence start is 1.0, which is 1.1 s away
        // (> 1.0 s threshold). Expected: no forward snap; falls back to starts[0] = 0.
        let snapped = SentenceSnap.snap(words: words, proposedIn: -0.1, proposedOut: 0.7)
        XCTAssertEqual(snapped?.start, 0.0, "just beyond threshold: no forward snap, use starts[0]")
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

    func testInForwardSnapThresholdMatchesSpec() {
        // The spec says "within ~1.0s BEFORE a sentence start" — verify the
        // constant is exactly 1.0 so the forward-snap window is deterministic.
        XCTAssertEqual(SentenceSnap.inForwardSnapThreshold, 1.0,
                       "forward-snap threshold must be 1.0 s per spec")
    }

    // MARK: - buildSentences (QuoteCaptureProcessor helper)

    func testBuildSentencesPartitionsAndMarkIsIn() {
        // The buffer words span two sentences; snapped span covers the second.
        // Expected: sentence 0 is NOT in (before snappedStart), sentence 1 IS.
        let bufWords: [WordTiming] = [
            WordTiming(word: "First.", start: 0.0, end: 0.5),
            WordTiming(word: "Second", start: 0.6, end: 0.9),
            WordTiming(word: "sentence.", start: 1.0, end: 1.4),
        ]
        let sentences = QuoteCaptureProcessor.buildSentences(
            from: bufWords, snappedStart: 0.55, snappedEnd: 1.4
        )
        XCTAssertEqual(sentences.count, 2)
        XCTAssertEqual(sentences[0].text, "First.")
        XCTAssertFalse(sentences[0].isInInitialSpan,
                       "sentence before snappedStart should be context-only")
        XCTAssertEqual(sentences[1].text, "Second sentence.")
        XCTAssertTrue(sentences[1].isInInitialSpan,
                      "sentence overlapping the snapped span should start in-quote")
    }

    func testBuildSentencesEmptyWordsReturnsEmpty() {
        XCTAssertTrue(
            QuoteCaptureProcessor.buildSentences(from: [], snappedStart: 0, snappedEnd: 5).isEmpty
        )
    }

    func testBuildSentencesSingleSentenceIsAlwaysIn() {
        let w = [WordTiming(word: "Done.", start: 0, end: 1)]
        let s = QuoteCaptureProcessor.buildSentences(from: w, snappedStart: 0, snappedEnd: 1)
        XCTAssertEqual(s.count, 1)
        XCTAssertTrue(s[0].isInInitialSpan)
    }
}
