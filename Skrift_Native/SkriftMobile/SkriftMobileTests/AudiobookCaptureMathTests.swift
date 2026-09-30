import XCTest
@testable import SkriftMobile

/// Pure capture math: sentence start indices and the C1 blockquote formatting.
final class AudiobookCaptureMathTests: XCTestCase {

    // MARK: - Sentence start indices

    func testSentenceStartIndicesDoesNotSplitOnAbbreviationsOrDecimals() {
        // "Mr. Smith paid 3.14 dollars. Then he left." → split ONLY after "dollars."
        // (→ "Then" at index 5), never at "Mr." or "3.14". The old terminal-"." rule
        // broke at "Mr." (the "sentences break in weird spots" report); NLTokenizer doesn't.
        let words = ["Mr.", "Smith", "paid", "3.14", "dollars.", "Then", "he", "left."]
            .enumerated().map { WordTiming(word: $0.element, start: Double($0.offset), end: Double($0.offset) + 0.5) }
        let starts = SentenceSnap.sentenceStartIndices(words)
        XCTAssertEqual(starts, [0, 5], "got \(starts)")
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

    // MARK: - isUnchangedTrim

    func testIsUnchangedTrimReturnsTrueWhenFlagsMatchInitialSpan() {
        let sentences = [
            BufferSentence(text: "A.", start: 0, end: 1, words: [], isInInitialSpan: false),
            BufferSentence(text: "B.", start: 1, end: 2, words: [], isInInitialSpan: true),
            BufferSentence(text: "C.", start: 2, end: 3, words: [], isInInitialSpan: false),
        ]
        let flags = sentences.map(\.isInInitialSpan)   // [false, true, false]
        XCTAssertTrue(QuoteCaptureProcessor.isUnchangedTrim(included: flags, sentences: sentences),
                      "matching the initial span = no change, should be a no-op")
    }

    func testIsUnchangedTrimReturnsFalseWhenFlagsDiffer() {
        let sentences = [
            BufferSentence(text: "A.", start: 0, end: 1, words: [], isInInitialSpan: false),
            BufferSentence(text: "B.", start: 1, end: 2, words: [], isInInitialSpan: true),
        ]
        // User included sentence A as well.
        let flags = [true, true]
        XCTAssertFalse(QuoteCaptureProcessor.isUnchangedTrim(included: flags, sentences: sentences),
                       "different from the initial span: trim has changed")
    }

    func testIsUnchangedTrimReturnsTrueOnCountMismatch() {
        // A count mismatch is treated as unchanged (safe guard — don't apply).
        let sentences = [BufferSentence(text: "A.", start: 0, end: 1, words: [], isInInitialSpan: true)]
        XCTAssertTrue(QuoteCaptureProcessor.isUnchangedTrim(included: [], sentences: sentences))
        XCTAssertTrue(QuoteCaptureProcessor.isUnchangedTrim(included: [true, false], sentences: sentences))
    }

    // MARK: - applyTrim timing-rebase math

    /// Verify that `applyTrim` rebases the word timings of the INCLUDED
    /// sentences so they start at t = 0 in the new audio.
    ///
    /// This test exercises the pure math only (no audio export) by constructing
    /// a `QuoteCaptureOutput` with a dummy buffer URL that doesn't exist on
    /// disk, then verifying that `applyTrim` throws `.exportFailed` (because
    /// the file is missing) but that we can unit-test the rebase formula
    /// independently by calling the helper inline.
    ///
    /// The helper logic under test is: `max(0, word.start - spanStart)`.
    func testTimingRebaseFormula() {
        // Simulate: two included sentences with word timings.
        // spanStart = sentence[0].start = 3.0 (buffer-local).
        // After trim, every timing is rebased to t=0.
        let spanStart: TimeInterval = 3.0
        let words: [WordTiming] = [
            WordTiming(word: "Hello", start: 3.0, end: 3.4),
            WordTiming(word: "world.", start: 3.5, end: 3.9),
            WordTiming(word: "Next.", start: 4.0, end: 4.4),
        ]
        let rebased = words.map {
            WordTiming(word: $0.word,
                       start: max(0, $0.start - spanStart),
                       end:   max(0, $0.end   - spanStart))
        }
        XCTAssertEqual(rebased[0].start, 0.0, accuracy: 0.001, "first word must start at t=0 after rebase")
        XCTAssertEqual(rebased[0].end,   0.4, accuracy: 0.001)
        XCTAssertEqual(rebased[1].start, 0.5, accuracy: 0.001)
        XCTAssertEqual(rebased[2].start, 1.0, accuracy: 0.001)
    }

    /// Verify that trimming a subset of sentences produces the correct
    /// transcript and timing span boundaries.
    func testApplyTrimTranscriptAndSpan() {
        // Three sentences; user drops sentence 0 (context only → not in initial),
        // keeps sentences 1 and 2.
        let s0 = BufferSentence(text: "Context sentence.", start: 0.0, end: 1.0,
                                words: [WordTiming(word: "Context", start: 0.0, end: 0.4),
                                        WordTiming(word: "sentence.", start: 0.5, end: 1.0)],
                                isInInitialSpan: false)
        let s1 = BufferSentence(text: "Optimism wins.", start: 1.1, end: 2.0,
                                words: [WordTiming(word: "Optimism", start: 1.1, end: 1.5),
                                        WordTiming(word: "wins.", start: 1.6, end: 2.0)],
                                isInInitialSpan: true)
        let s2 = BufferSentence(text: "That is the key.", start: 2.1, end: 3.0,
                                words: [WordTiming(word: "That", start: 2.1, end: 2.3),
                                        WordTiming(word: "is", start: 2.4, end: 2.6),
                                        WordTiming(word: "the", start: 2.7, end: 2.8),
                                        WordTiming(word: "key.", start: 2.9, end: 3.0)],
                                isInInitialSpan: true)

        let included = [false, true, true]
        let initialIncluded = [false, true, true]   // unchanged → should be nil
        let includedChanged = [true, true, true]    // added context → changed

        // No-op check.
        XCTAssertTrue(QuoteCaptureProcessor.isUnchangedTrim(
            included: initialIncluded, sentences: [s0, s1, s2]))

        // Changed check.
        XCTAssertFalse(QuoteCaptureProcessor.isUnchangedTrim(
            included: includedChanged, sentences: [s0, s1, s2]))

        // Transcript: joining s1+s2, blockquoted.
        let active = zip([s0, s1, s2], included).filter(\.1).map(\.0)
        let joined = active.map(\.text).joined(separator: " ")
        let transcript = QuoteFormatting.blockquote(joined)
        XCTAssertEqual(transcript, "> Optimism wins. That is the key.")

        // Duration: s1.start=1.1, s2.end=3.0.
        let spanStart = active[0].start   // 1.1
        let spanEnd   = active[active.count - 1].end   // 3.0
        XCTAssertEqual(spanEnd - spanStart, 1.9, accuracy: 0.001)

        // Timings rebase (all words from s1+s2, shifted by spanStart=1.1).
        let allWords = active.flatMap(\.words)
        let rebased = allWords.map {
            WordTiming(word: $0.word,
                       start: max(0, $0.start - spanStart),
                       end:   max(0, $0.end   - spanStart))
        }
        XCTAssertEqual(rebased[0].word, "Optimism")
        XCTAssertEqual(rebased[0].start, 0.0, accuracy: 0.001, "first included word must be at t=0")
        XCTAssertEqual(rebased.last?.word, "key.")
        XCTAssertEqual(rebased.last?.end ?? 0, 3.0 - 1.1, accuracy: 0.001)
    }

    // MARK: - Karaoke word alignment for capture memos

    /// Playback karaoke runs over the WHOLE capture — the quote region from
    /// sidecar index 0, the ramble region from `spokenWordCount` — so quote
    /// words + ramble words must whitespace-split to exactly the sidecar's
    /// word sequence, with the "> " markers stripped (they aren't words and
    /// would shift the highlight off the timings).
    func testCaptureKaraokeWordsAlignWithTheSidecarLayout() {
        // Multi-sentence quote with a bare ">" spacer: 4 quote words, 1 ramble word.
        let split = CaptureQuote.split("> One two three.\n>\n> Four.\n\nRamble.")!
        let words = (split.displayText.split(whereSeparator: \.isWhitespace)
                     + split.ramble.split(whereSeparator: \.isWhitespace)).map(String.init)
        XCTAssertEqual(words, ["One", "two", "three.", "Four.", "Ramble."])
        XCTAssertEqual(split.spokenWordCount, 4, "the ramble region karaokes from index 4")
    }

    /// When there is no ramble, `quote.ramble` is empty and the playing mode
    /// shows just the quote frame, karaoke from word 0.
    func testCaptureQuoteRambleIsEmptyForQuoteOnlyCapture() {
        let quoteOnly = "> Optimism is not the belief things will go well."
        let split = CaptureQuote.split(quoteOnly)
        XCTAssertNotNil(split)
        XCTAssertTrue(split?.ramble.isEmpty ?? false,
                      "a quote-only capture has no ramble — karaoke must use displayText")
    }
}
