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

    func testBuildSentencesPartitionsWords() {
        // The words span two sentences.
        let bufWords: [WordTiming] = [
            WordTiming(word: "First.", start: 0.0, end: 0.5),
            WordTiming(word: "Second", start: 0.6, end: 0.9),
            WordTiming(word: "sentence.", start: 1.0, end: 1.4),
        ]
        let sentences = QuoteCaptureProcessor.buildSentences(from: bufWords)
        XCTAssertEqual(sentences.count, 2)
        XCTAssertEqual(sentences[0].text, "First.")
        XCTAssertEqual(sentences[1].text, "Second sentence.")
    }

    func testBuildSentencesEmptyWordsReturnsEmpty() {
        XCTAssertTrue(QuoteCaptureProcessor.buildSentences(from: []).isEmpty)
    }

    func testBuildSentencesSingleSentence() {
        let w = [WordTiming(word: "Done.", start: 0, end: 1)]
        let s = QuoteCaptureProcessor.buildSentences(from: w)
        XCTAssertEqual(s.count, 1)
        XCTAssertEqual(s[0].text, "Done.")
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
