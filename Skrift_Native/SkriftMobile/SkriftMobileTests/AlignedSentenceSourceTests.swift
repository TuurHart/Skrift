import XCTest
@testable import SkriftMobile

/// `AlignedSentenceSource` — the per-sentence-fallback selection layer between
/// a book's alignment sidecar and the read-along / capture UIs
/// (`LANES-2026-07-21C/BASE.md`). Fixtures build `FileAlignment`/`AlignedSentence`
/// inline (no store IO, no ZIPFoundation — those are LANE_CORE's territory).
final class AlignedSentenceSourceTests: XCTestCase {

    // MARK: - Fixture helpers

    private func makeWord(_ w: String, _ start: TimeInterval, _ end: TimeInterval) -> WordTiming {
        WordTiming(word: w, start: start, end: end)
    }

    private func makeSentence(
        _ text: String, start: TimeInterval, end: TimeInterval,
        wordStart: Int, wordEnd: Int, confidence: Double,
        words: [WordTiming]? = nil, sourceFile: String? = "ch1.xhtml"
    ) -> AlignedSentence {
        AlignedSentence(
            text: text, start: start, end: end, wordStart: wordStart, wordEnd: wordEnd,
            confidence: confidence,
            words: words ?? [WordTiming(word: text, start: start, end: end)],
            sourceFile: sourceFile
        )
    }

    private func makeAlignment(
        verdict: String = AlignmentCore.Verdict.aligned.rawValue,
        sentences: [AlignedSentence]
    ) -> FileAlignment {
        FileAlignment(
            schema: 1, fileIndex: 0, transcriptSignature: "sig:100", epubSignature: "epubsig",
            verdict: verdict, chapterMarks: [], sentences: sentences
        )
    }

    // MARK: - nil gates

    func testNilWhenAlignmentMissing() {
        let result = AlignedSentenceSource.sentences(
            alignment: nil, isFresh: true, transcriptWords: [],
            snappedStart: 0, snappedEnd: 0
        )
        XCTAssertNil(result)
    }

    func testNilWhenStale() {
        let fa = makeAlignment(sentences: [
            makeSentence("Hi.", start: 0, end: 1, wordStart: 0, wordEnd: 1, confidence: 0.9)
        ])
        let result = AlignedSentenceSource.sentences(
            alignment: fa, isFresh: false, transcriptWords: [],
            snappedStart: 0, snappedEnd: 0
        )
        XCTAssertNil(result, "a stale alignment must fall back to the caller's ASR-only builder")
    }

    func testNilWhenVerdictNotAligned() {
        for verdict in [AlignmentCore.Verdict.partial.rawValue, AlignmentCore.Verdict.rejected.rawValue] {
            let fa = makeAlignment(verdict: verdict, sentences: [
                makeSentence("Hi.", start: 0, end: 1, wordStart: 0, wordEnd: 1, confidence: 0.9)
            ])
            let result = AlignedSentenceSource.sentences(
                alignment: fa, isFresh: true, transcriptWords: [],
                snappedStart: 0, snappedEnd: 0
            )
            XCTAssertNil(result, "verdict \(verdict) must not build a sentence list")
        }
    }

    // MARK: - Full-aligned mapping (confidence >= floor)

    func testFullAlignedMappingPreservesTextTimesAndWords() {
        let s1Words = [makeWord("In", 0.0, 0.4), makeWord("span.", 0.4, 1.0)]
        let s2Words = [makeWord("Out", 5.0, 5.4), makeWord("of", 5.4, 5.6), makeWord("span.", 5.6, 6.0)]
        let s1 = makeSentence("In span.", start: 0.0, end: 1.0, wordStart: 0, wordEnd: 2,
                              confidence: 0.9, words: s1Words)
        let s2 = makeSentence("Out of span.", start: 5.0, end: 6.0, wordStart: 2, wordEnd: 5,
                              confidence: 0.9, words: s2Words)
        let fa = makeAlignment(sentences: [s1, s2])

        let result = AlignedSentenceSource.sentences(
            alignment: fa, isFresh: true, transcriptWords: [],
            snappedStart: 0.5, snappedEnd: 2.0
        )

        guard let result, result.count == 2 else {
            return XCTFail("expected exactly 2 sentences, got \(result?.count ?? -1)")
        }
        XCTAssertEqual(result[0].text, "In span.")
        XCTAssertEqual(result[0].start, 0.0)
        XCTAssertEqual(result[0].end, 1.0)
        XCTAssertEqual(result[0].words, s1Words)
        XCTAssertEqual(result[0].isInInitialSpan, true, "1.0 > 0.5 && 0.0 < 2.0")

        XCTAssertEqual(result[1].text, "Out of span.")
        XCTAssertEqual(result[1].words, s2Words)
        XCTAssertEqual(result[1].isInInitialSpan, false, "5.0 is not < snappedEnd(2.0)")
    }

    func testConfidenceExactlyFloorIsTrusted() {
        // Symbolic, not the literal 0.5 — this pins the `>=` (not `>`) operator,
        // whatever the floor's actual value is.
        let s = makeSentence("Exactly trusted.", start: 0, end: 1, wordStart: 0, wordEnd: 2,
                             confidence: AlignedSentenceSource.confidenceFloor)
        let fa = makeAlignment(sentences: [s])
        let result = AlignedSentenceSource.sentences(
            alignment: fa, isFresh: true, transcriptWords: [],
            snappedStart: 0, snappedEnd: 0
        )
        XCTAssertEqual(result?.count, 1)
        XCTAssertEqual(result?.first?.text, "Exactly trusted.",
                       "confidence == floor must be trusted (>=, not >)")
    }

    // MARK: - Low-confidence ASR splice (confidence < floor)

    func testLowConfidenceSplicesASRWordsVerbatim() {
        let transcriptWords = [
            makeWord("Hello", 0.0, 0.3),
            makeWord("wurld", 0.3, 0.6),      // an ASR mishear the aligner didn't trust
            makeWord("today.", 0.6, 1.0),
        ]
        let untrusted = makeSentence(
            "Hello world today.", start: 0.0, end: 1.0, wordStart: 0, wordEnd: 3, confidence: 0.2
        )
        let fa = makeAlignment(sentences: [untrusted])

        let result = AlignedSentenceSource.sentences(
            alignment: fa, isFresh: true, transcriptWords: transcriptWords,
            snappedStart: 0, snappedEnd: 0
        )

        XCTAssertEqual(result?.count, 1)
        XCTAssertEqual(result?.first?.text, "Hello wurld today.",
                       "below the confidence floor, the raw ASR words win over the aligned book text")
        XCTAssertEqual(result?.first?.words, transcriptWords)
    }

    func testLowConfidenceSpliceMultiSentenceOrderingPreserved() {
        // A single low-confidence AlignedSentence whose word slice actually
        // contains a sentence break — the ASR re-partition must yield BOTH
        // sentences, left-to-right, not one merged block.
        let transcriptWords = [
            makeWord("Stop.", 0.0, 0.3),
            makeWord("Go", 0.3, 0.6),
            makeWord("now.", 0.6, 1.0),
        ]
        let untrusted = makeSentence(
            "Stop go now.", start: 0.0, end: 1.0, wordStart: 0, wordEnd: 3, confidence: 0.1
        )
        let fa = makeAlignment(sentences: [untrusted])

        let result = AlignedSentenceSource.sentences(
            alignment: fa, isFresh: true, transcriptWords: transcriptWords,
            snappedStart: 0, snappedEnd: 0
        )

        guard let result, result.count == 2 else {
            return XCTFail("expected the splice to re-partition into exactly 2 sentences, got \(result?.count ?? -1)")
        }
        XCTAssertEqual(result[0].text, "Stop.")
        XCTAssertEqual(result[1].text, "Go now.")
        XCTAssertLessThan(result[0].start, result[1].start, "ordering preserved, left to right")
    }

    func testLowConfidenceSpliceOutOfRangeYieldsNothing() {
        // wordStart/wordEnd point past a (freakishly) shorter transcriptWords
        // array than the alignment expected — must degrade to nothing, never
        // trap and never fabricate a sentence from a bad slice.
        let untrusted = makeSentence(
            "Untrustworthy.", start: 0, end: 1, wordStart: 10, wordEnd: 12, confidence: 0.1
        )
        let fa = makeAlignment(sentences: [untrusted])
        let result = AlignedSentenceSource.sentences(
            alignment: fa, isFresh: true, transcriptWords: [makeWord("only", 0, 0.2)],
            snappedStart: 0, snappedEnd: 0
        )
        XCTAssertEqual(result?.count, 0)
    }

    // MARK: - Mixed list: sorted + deterministic

    func testMixedListSortedByStart() {
        // wordStart/wordEnd are indices into the FULL file transcript
        // (matching real usage — ReadAlongView/MergedCaptureView pass the
        // whole `ft.words`), so the low-confidence sentence's splice range
        // must actually land on its two words below.
        let low = makeSentence("Second, low-confidence.", start: 5.0, end: 6.0,
                               wordStart: 0, wordEnd: 2, confidence: 0.1)
        let high = makeSentence("First.", start: 0.0, end: 1.0,
                                wordStart: 0, wordEnd: 2, confidence: 0.9)
        // Deliberately scrambled input order, mixing a low-confidence splice
        // with a directly-mapped sentence.
        let fa = makeAlignment(sentences: [low, high])
        let transcriptWords = [
            makeWord("Second,", 5.0, 5.4), makeWord("spliced.", 5.4, 6.0),
        ]
        let result = AlignedSentenceSource.sentences(
            alignment: fa, isFresh: true, transcriptWords: transcriptWords,
            snappedStart: 0, snappedEnd: 0
        )
        XCTAssertEqual(result?.map(\.text), ["First.", "Second, spliced."])
    }

    func testDeterminism() {
        // A. is trusted (mapped directly); B. is a low-confidence splice —
        // exercises both paths together, run twice.
        let fa = makeAlignment(sentences: [
            makeSentence("A.", start: 0, end: 1, wordStart: 0, wordEnd: 1, confidence: 0.9),
            makeSentence("B.", start: 1, end: 2, wordStart: 0, wordEnd: 1, confidence: 0.2),
        ])
        let words = [makeWord("B.", 1, 2)]
        let r1 = AlignedSentenceSource.sentences(alignment: fa, isFresh: true, transcriptWords: words,
                                                  snappedStart: 0, snappedEnd: 0)
        let r2 = AlignedSentenceSource.sentences(alignment: fa, isFresh: true, transcriptWords: words,
                                                  snappedStart: 0, snappedEnd: 0)
        XCTAssertEqual(r1?.count, 2)
        XCTAssertEqual(r1, r2)
    }

    // MARK: - Gap fill (2026-07-22 Odyssey device report: spoken text vanished)

    /// The Trojan War case: a sentence present in the audio (and the ePub) that the
    /// aligner missed — `assembleSentences` dropped it (zero timed words), so the
    /// read-along jumped over it while the narrator read it. The uncovered ASR words
    /// must render as transcript sentences, sorted into place.
    func testAlignerHoleBetweenSentencesFilledWithASR() {
        let transcriptWords = [
            makeWord("First", 0.0, 0.4), makeWord("sentence.", 0.4, 1.0),           // covered by s1
            makeWord("It", 2.0, 2.2), makeWord("is", 2.2, 2.4),                     // the hole
            makeWord("not", 2.4, 2.6), makeWord("the", 2.6, 2.8),
            makeWord("Trojan", 2.8, 3.2), makeWord("War.", 3.2, 3.8),
            makeWord("Last", 8.0, 8.4), makeWord("sentence.", 8.4, 9.0),            // covered by s2
        ]
        let s1 = makeSentence("First sentence.", start: 0.0, end: 1.0,
                              wordStart: 0, wordEnd: 2, confidence: 0.9)
        let s2 = makeSentence("Last sentence.", start: 8.0, end: 9.0,
                              wordStart: 8, wordEnd: 10, confidence: 0.9)
        let fa = makeAlignment(sentences: [s1, s2])

        let result = AlignedSentenceSource.sentences(
            alignment: fa, isFresh: true, transcriptWords: transcriptWords,
            snappedStart: 0, snappedEnd: 0
        )
        XCTAssertEqual(result?.map(\.text),
                       ["First sentence.", "It is not the Trojan War.", "Last sentence."],
                       "the hole's ASR words must appear, in time order — never a silent jump")
    }

    func testBoundaryFuzzBelowMinWordsStaysSilent() {
        // A 1–2 word gap between adjacent sentences' splice ranges is time fuzz,
        // not missing narration — filling it would sprinkle fragments everywhere.
        let transcriptWords = [
            makeWord("One.", 0.0, 0.5),
            makeWord("stray", 0.5, 0.9), makeWord("bits", 0.9, 1.2),   // 2-word gap
            makeWord("Two.", 2.0, 2.5),
        ]
        let fa = makeAlignment(sentences: [
            makeSentence("One.", start: 0.0, end: 0.5, wordStart: 0, wordEnd: 1, confidence: 0.9),
            makeSentence("Two.", start: 2.0, end: 2.5, wordStart: 3, wordEnd: 4, confidence: 0.9),
        ])
        let result = AlignedSentenceSource.sentences(
            alignment: fa, isFresh: true, transcriptWords: transcriptWords,
            snappedStart: 0, snappedEnd: 0
        )
        XCTAssertEqual(result?.map(\.text), ["One.", "Two."])
    }

    func testLeadingAndTrailingHolesFilled() {
        // Opening credits before the book text starts, end matter after it stops —
        // both are spoken, both must show.
        let transcriptWords = [
            makeWord("This", 0.0, 0.2), makeWord("is", 0.2, 0.4), makeWord("Audible.", 0.4, 1.0),
            makeWord("Book", 5.0, 5.5), makeWord("text.", 5.5, 6.0),
            makeWord("The", 9.0, 9.2), makeWord("end", 9.2, 9.4), makeWord("credits.", 9.4, 10.0),
        ]
        let fa = makeAlignment(sentences: [
            makeSentence("Book text.", start: 5.0, end: 6.0, wordStart: 3, wordEnd: 5, confidence: 0.9),
        ])
        let result = AlignedSentenceSource.sentences(
            alignment: fa, isFresh: true, transcriptWords: transcriptWords,
            snappedStart: 0, snappedEnd: 0
        )
        XCTAssertEqual(result?.map(\.text), ["This is Audible.", "Book text.", "The end credits."])
    }

    func testLowConfidenceSpliceRangeCountsAsCoveredNoDuplication() {
        // The untrusted sentence already renders words 0..<3 verbatim — gap fill
        // must not show them a second time.
        let transcriptWords = [
            makeWord("Hello", 0.0, 0.3), makeWord("wurld", 0.3, 0.6), makeWord("today.", 0.6, 1.0),
        ]
        let fa = makeAlignment(sentences: [
            makeSentence("Hello world today.", start: 0.0, end: 1.0,
                         wordStart: 0, wordEnd: 3, confidence: 0.2),
        ])
        let result = AlignedSentenceSource.sentences(
            alignment: fa, isFresh: true, transcriptWords: transcriptWords,
            snappedStart: 0, snappedEnd: 0
        )
        XCTAssertEqual(result?.map(\.text), ["Hello wurld today."])
    }

    /// Schema 4: a BRIDGED sentence (aligner hole, corroborated sandwich) carries
    /// confidence 0 by design — the flag, not the confidence, makes it render as book
    /// text. Its splice range also counts as covered, so gap fill never doubles it.
    func testBridgedSentenceRendersBookTextNotASR() {
        let transcriptWords = [
            makeWord("gamma", 2.0, 2.5), makeWord("delta", 2.5, 3.0), makeWord("epsilon", 3.0, 3.5),
        ]
        var bridged = makeSentence("Gamma delta epsilon.", start: 2.0, end: 3.5,
                                   wordStart: 0, wordEnd: 3, confidence: 0)
        bridged.bridged = true
        let fa = makeAlignment(sentences: [bridged])
        let result = AlignedSentenceSource.sentences(
            alignment: fa, isFresh: true, transcriptWords: transcriptWords,
            snappedStart: 0, snappedEnd: 0
        )
        XCTAssertEqual(result?.map(\.text), ["Gamma delta epsilon."],
                       "book text renders once — no ASR splice, no gap-fill duplicate")
    }

    func testUncoveredWordRangesUnionsOverlapsAndClamps() {
        let overlapping = [
            makeSentence("A.", start: 0, end: 1, wordStart: 3, wordEnd: 8, confidence: 0.9),
            makeSentence("B.", start: 1, end: 2, wordStart: 0, wordEnd: 5, confidence: 0.9),
            makeSentence("C.", start: 2, end: 3, wordStart: 9, wordEnd: 99, confidence: 0.9),  // stale hi clamps
        ]
        XCTAssertEqual(AlignedSentenceSource.uncoveredWordRanges(sentences: overlapping, wordCount: 12),
                       [8..<9], "overlaps union; out-of-range splices clamp instead of trapping")
        XCTAssertEqual(AlignedSentenceSource.uncoveredWordRanges(sentences: [], wordCount: 4),
                       [0..<4], "no sentences → the whole transcript is a hole")
        XCTAssertEqual(AlignedSentenceSource.uncoveredWordRanges(sentences: overlapping, wordCount: 0),
                       [], "empty transcript → nothing to fill")
    }
}
