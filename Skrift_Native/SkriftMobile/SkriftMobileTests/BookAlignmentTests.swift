import XCTest
@testable import SkriftMobile

// 📖 spike 6 — BookAlignment.swift coverage. No ZIPFoundation here (the `.epub` branch of
// `parseBookFile` is exercised only via the app at the merge gate) — everything below feeds
// `[String: Data]`-free, pre-built values straight into the pure pieces.

// MARK: - Store: round-trip + schema gate

final class BookAlignmentStoreTests: XCTestCase {
    private func tempDir() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("al_\(UUID().uuidString)", isDirectory: true)
    }

    func testSaveLoadRoundTrip() throws {
        let store = BookAlignmentStore(directory: tempDir())
        let id = UUID()
        let sentence = AlignedSentence(
            text: "Hello world.", start: 0, end: 1, wordStart: 0, wordEnd: 2, confidence: 1,
            words: [WordTiming(word: "Hello", start: 0, end: 0.5), WordTiming(word: "world.", start: 0.5, end: 1)],
            sourceFile: "ch1.xhtml")
        let fa = FileAlignment(fileIndex: 0, transcriptSignature: "12:34", epubSignature: "abc",
                               verdict: "aligned", chapterMarks: [ChapterMark(title: "Ch 1", sentenceIndex: 0)],
                               sentences: [sentence])
        try store.save(fa, bookID: id)
        XCTAssertEqual(store.fileAlignment(bookID: id, fileIndex: 0), fa)
    }

    func testSchemaGateRejectsOldSchema() throws {
        let dir = tempDir()
        let store = BookAlignmentStore(directory: dir)
        let id = UUID()
        let fa = FileAlignment(schema: 0, fileIndex: 0, transcriptSignature: "1:1", epubSignature: "x", verdict: "rejected")
        let folder = dir.appendingPathComponent(id.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try JSONEncoder().encode(fa).write(to: folder.appendingPathComponent("alignment_f0.json"))
        XCTAssertNil(store.fileAlignment(bookID: id, fileIndex: 0))
    }

    /// Schema 3 (multi-text): a v2 sidecar (the last pre-multi-text schema, the realistic "old
    /// install" case) reads as absent too, same as any other stale schema — every attached text
    /// re-aligns fresh on the book's next open.
    func testSchemaGateRejectsV2Sidecar() throws {
        let dir = tempDir()
        let store = BookAlignmentStore(directory: dir)
        let id = UUID()
        let fa = FileAlignment(schema: 2, fileIndex: 0, transcriptSignature: "1:1", epubSignature: "x", verdict: "aligned")
        let folder = dir.appendingPathComponent(id.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try JSONEncoder().encode(fa).write(to: folder.appendingPathComponent("alignment_f0.json"))
        XCTAssertNil(store.fileAlignment(bookID: id, fileIndex: 0))
    }

    /// Schema 3 round-trip WITH the new fields populated (`sources`, `AlignedSentence.textFile`)
    /// — the plain round-trip above (`testSaveLoadRoundTrip`) never touches them; this confirms
    /// they persist correctly too.
    func testSchema3RoundTripWithSourcesAndTextFile() throws {
        let store = BookAlignmentStore(directory: tempDir())
        let id = UUID()
        let sentence = AlignedSentence(
            text: "Hello world.", start: 0, end: 1, wordStart: 0, wordEnd: 2, confidence: 1,
            words: [WordTiming(word: "Hello", start: 0, end: 0.5), WordTiming(word: "world.", start: 0.5, end: 1)],
            sourceFile: "ch1.xhtml", textFile: "a.epub")
        var fa = FileAlignment(fileIndex: 0, transcriptSignature: "12:34", epubSignature: "abc", verdict: "aligned",
                               chapterMarks: [ChapterMark(title: "Ch 1", sentenceIndex: 0)], sentences: [sentence])
        fa.sources = [AlignmentSource(textFilename: "a.epub", title: "Book A", verdict: "aligned", coverage: 0.9)]
        try store.save(fa, bookID: id)
        let loaded = store.fileAlignment(bookID: id, fileIndex: 0)
        XCTAssertEqual(loaded, fa)
        XCTAssertEqual(loaded?.sentences.first?.textFile, "a.epub")
        XCTAssertEqual(loaded?.sources.first?.title, "Book A")
    }

    /// Schema 4 (bridged holes): a v3 sidecar reads as absent, so every attached book
    /// re-aligns on its next open and existing installs gain bridges + re-derived marks
    /// without user action.
    func testSchemaGateRejectsV3Sidecar() throws {
        let dir = tempDir()
        let store = BookAlignmentStore(directory: dir)
        let id = UUID()
        let fa = FileAlignment(schema: 3, fileIndex: 0, transcriptSignature: "1:1", epubSignature: "x", verdict: "aligned")
        let folder = dir.appendingPathComponent(id.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try JSONEncoder().encode(fa).write(to: folder.appendingPathComponent("alignment_f0.json"))
        XCTAssertNil(store.fileAlignment(bookID: id, fileIndex: 0))
    }

    func testBridgedFlagPersists() throws {
        let store = BookAlignmentStore(directory: tempDir())
        let id = UUID()
        var sentence = AlignedSentence(text: "Bridged.", start: 2, end: 4, wordStart: 0, wordEnd: 1,
                                       confidence: 0, words: [], sourceFile: "ch1.xhtml", textFile: "a.epub")
        sentence.bridged = true
        let fa = FileAlignment(fileIndex: 0, transcriptSignature: "1:1", epubSignature: "x",
                               verdict: "aligned", chapterMarks: [], sentences: [sentence])
        try store.save(fa, bookID: id)
        XCTAssertEqual(store.fileAlignment(bookID: id, fileIndex: 0)?.sentences.first?.bridged, true)
    }

    func testMissingReturnsNil() {
        XCTAssertNil(BookAlignmentStore(directory: tempDir()).fileAlignment(bookID: UUID(), fileIndex: 0))
    }

    func testSaveCreatesBookFolder() throws {
        let dir = tempDir()
        let store = BookAlignmentStore(directory: dir)
        let id = UUID()
        try store.save(FileAlignment(fileIndex: 3, transcriptSignature: "", epubSignature: "", verdict: "partial"), bookID: id)
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.sidecarURL(bookID: id, fileIndex: 3).path))
    }
}

// MARK: - Freshness

final class BookAlignmentFreshnessTests: XCTestCase {
    private func tempDir() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("fresh_\(UUID().uuidString)", isDirectory: true)
    }

    private func missingAudioURL() -> URL {
        // A path that doesn't exist — `BookTranscriptStore.signature(forFileAt:)` returns ""
        // for it, which we exploit as a stable, file-free staleness key both sides can agree on.
        URL(fileURLWithPath: "/tmp/skrift-align-test-\(UUID().uuidString).m4a")
    }

    func testFreshWhenSignatureMatchesCurrentTranscript() throws {
        let dir = tempDir()
        let bookID = UUID()
        let transcriptStore = BookTranscriptStore(directory: dir)
        let ft = FileTranscript(fileIndex: 0, signature: "", coveredUpTo: 42, words: [WordTiming(word: "a", start: 0, end: 1)])
        try transcriptStore.save(ft, bookID: bookID)

        let alignmentStore = BookAlignmentStore(directory: dir)
        let fa = FileAlignment(fileIndex: 0, transcriptSignature: FileAlignment.signature(forTranscript: ft),
                               epubSignature: "e", verdict: "aligned")
        XCTAssertTrue(alignmentStore.isFresh(fa, bookID: bookID, fileIndex: 0, audioURL: missingAudioURL()))
    }

    func testStaleWhenSignatureDiffersFromCurrentTranscript() throws {
        let dir = tempDir()
        let bookID = UUID()
        let transcriptStore = BookTranscriptStore(directory: dir)
        let ft = FileTranscript(fileIndex: 0, signature: "", coveredUpTo: 42, words: [WordTiming(word: "a", start: 0, end: 1)])
        try transcriptStore.save(ft, bookID: bookID)

        let alignmentStore = BookAlignmentStore(directory: dir)
        let fa = FileAlignment(fileIndex: 0, transcriptSignature: "0:0", epubSignature: "e", verdict: "aligned")
        XCTAssertFalse(alignmentStore.isFresh(fa, bookID: bookID, fileIndex: 0, audioURL: missingAudioURL()))
    }

    func testStaleWhenNoTranscriptAtAll() {
        let alignmentStore = BookAlignmentStore(directory: tempDir())
        let fa = FileAlignment(fileIndex: 0, transcriptSignature: "1:1", epubSignature: "e", verdict: "aligned")
        XCTAssertFalse(alignmentStore.isFresh(fa, bookID: UUID(), fileIndex: 0, audioURL: missingAudioURL()))
    }
}

// MARK: - mergeBlocksByFile (the local-word-index fix)

final class MergeBlocksByFileTests: XCTestCase {
    func testAdjacentSameFileBlocksMerge() {
        let blocks = [EPubBlock(text: "Para one.", sourceFile: "a.xhtml"),
                     EPubBlock(text: "Para two.", sourceFile: "a.xhtml"),
                     EPubBlock(text: "Different file.", sourceFile: "b.xhtml")]
        let merged = BookAlignmentRunner.mergeBlocksByFile(blocks)
        XCTAssertEqual(merged.count, 2)
        XCTAssertEqual(merged[0].sourceFile, "a.xhtml")
        XCTAssertEqual(merged[0].text, "Para one. Para two.")
        XCTAssertEqual(merged[1].sourceFile, "b.xhtml")
        XCTAssertEqual(merged[1].text, "Different file.")
    }

    func testNonContiguousSameFileStaysSeparate() {
        // Defensive fallback (see doc comment): same sourceFile but not adjacent degrades to
        // separate merged blocks rather than merging across the gap — never the shape EPubParse
        // actually emits (spine order), just a safety net.
        let blocks = [EPubBlock(text: "A1", sourceFile: "a.xhtml"),
                     EPubBlock(text: "B1", sourceFile: "b.xhtml"),
                     EPubBlock(text: "A2", sourceFile: "a.xhtml")]
        let merged = BookAlignmentRunner.mergeBlocksByFile(blocks)
        XCTAssertEqual(merged.map(\.sourceFile), ["a.xhtml", "b.xhtml", "a.xhtml"])
    }

    func testEmptyInput() {
        XCTAssertEqual(BookAlignmentRunner.mergeBlocksByFile([]), [])
    }
}

// MARK: - assembleSentences (pure sentence assembly)

final class SentenceAssemblyTests: XCTestCase {
    func testTimesDistributedLinearlyAndConfidenceComputed() {
        let text = "The quick brown fox jumps. Over the lazy dog."
        let ranges = [AlignmentCore.Result.MatchedRange(sourceFile: "f", bookWordStart: 0, bookWordEnd: 5, start: 0, end: 5)]
        let transcript = [
            WordTiming(word: "The", start: 0, end: 1), WordTiming(word: "quick", start: 1, end: 2),
            WordTiming(word: "brown", start: 2, end: 3), WordTiming(word: "fox", start: 3, end: 4),
            WordTiming(word: "jumps", start: 4, end: 5),
        ]
        let sentences = BookAlignmentRunner.assembleSentences(text: text, sourceFile: "f",
                                                               matchedRanges: ranges, transcriptWords: transcript)
        // The second sentence ("Over the lazy dog.") got zero timed words → dropped.
        XCTAssertEqual(sentences.count, 1)
        let s = sentences[0]
        XCTAssertEqual(s.text, "The quick brown fox jumps.")
        XCTAssertEqual(s.sourceFile, "f")
        XCTAssertEqual(s.words.count, 5)
        XCTAssertEqual(s.confidence, 1.0, accuracy: 0.0001)
        XCTAssertEqual(s.start, 0, accuracy: 0.001)
        XCTAssertEqual(s.end, 5, accuracy: 0.001)
        // 5 words evenly spanning [0,5] → "quick" (2nd) lands at [1,2].
        XCTAssertEqual(s.words[1].start, 1, accuracy: 0.001)
        XCTAssertEqual(s.words[1].end, 2, accuracy: 0.001)
        XCTAssertEqual(s.wordStart, 0)
        XCTAssertEqual(s.wordEnd, 5)
    }

    /// 2026-07-22 drift fix: when the range carries the aligner's per-word times, assembly
    /// uses them VERBATIM (no linear re-distribution — that drifted mid-range words by
    /// seconds across pauses), and confidence counts only DIRECT-matched words.
    func testExactWordTimesUsedVerbatimAndConfidenceCountsDirectOnly() {
        let text = "Alpha beta gamma delta."
        // 4 words: alpha exact [0,1], beta exact [1,2], then a LONG PAUSE — gamma
        // interpolated at ~9.5, delta exact [10,11]. Linear distribution over the range
        // [0,11] would have put beta at ~2.75 and gamma at ~5.5 (seconds off).
        let wt: [AlignmentCore.Result.WordTime] = [
            .init(start: 0, end: 1, direct: true),
            .init(start: 1, end: 2, direct: true),
            .init(start: 9.5, end: 9.5, direct: false),
            .init(start: 10, end: 11, direct: true),
        ]
        let ranges = [AlignmentCore.Result.MatchedRange(sourceFile: "f", bookWordStart: 0,
                                                        bookWordEnd: 4, start: 0, end: 11,
                                                        wordTimes: wt)]
        let sentences = BookAlignmentRunner.assembleSentences(text: text, sourceFile: "f",
                                                               matchedRanges: ranges, transcriptWords: [])
        XCTAssertEqual(sentences.count, 1)
        let s = sentences[0]
        XCTAssertEqual(s.words[1].start, 1, accuracy: 0.001)      // exact, not 2.75
        XCTAssertEqual(s.words[2].start, 9.5, accuracy: 0.001)    // interpolated point time
        XCTAssertEqual(s.end, 11, accuracy: 0.001)
        XCTAssertEqual(s.confidence, 0.75, accuracy: 0.001)       // 3 direct of 4
    }

    func testPartialConfidenceWhenSomeWordsUnmatched() {
        let text = "Alpha beta gamma delta."
        // Only "gamma" (word index 2 of 4) gets a time; the rest of the sentence stays untimed.
        let ranges = [AlignmentCore.Result.MatchedRange(sourceFile: "f", bookWordStart: 2, bookWordEnd: 3, start: 10, end: 11)]
        let sentences = BookAlignmentRunner.assembleSentences(text: text, sourceFile: "f",
                                                               matchedRanges: ranges, transcriptWords: [])
        XCTAssertEqual(sentences.count, 1)
        XCTAssertEqual(sentences[0].text, text)   // full original text kept regardless of partial timing
        XCTAssertEqual(sentences[0].confidence, 0.25, accuracy: 0.001)
        XCTAssertEqual(sentences[0].words.count, 1)
        XCTAssertEqual(sentences[0].words[0].word, "gamma")
    }

    func testSentenceWithNoTimedWordsIsDropped() {
        let text = "Front matter nobody narrated."
        let sentences = BookAlignmentRunner.assembleSentences(text: text, sourceFile: "f",
                                                               matchedRanges: [], transcriptWords: [])
        XCTAssertTrue(sentences.isEmpty)
    }

    func testWrongSourceFileRangeIgnored() {
        let text = "One two three."
        let ranges = [AlignmentCore.Result.MatchedRange(sourceFile: "OTHER", bookWordStart: 0, bookWordEnd: 3, start: 0, end: 3)]
        let sentences = BookAlignmentRunner.assembleSentences(text: text, sourceFile: "f",
                                                               matchedRanges: ranges, transcriptWords: [])
        XCTAssertTrue(sentences.isEmpty)
    }

    func testEmptyTextReturnsNoSentences() {
        XCTAssertTrue(BookAlignmentRunner.assembleSentences(
            text: "", sourceFile: "f", matchedRanges: [], transcriptWords: []).isEmpty)
    }

    func testASRFallbackWordRangeCoversResolvedTimeSpan() {
        let text = "Gamma."
        let ranges = [AlignmentCore.Result.MatchedRange(sourceFile: "f", bookWordStart: 0, bookWordEnd: 1, start: 5, end: 6)]
        let transcript = [
            WordTiming(word: "before", start: 0, end: 1),
            WordTiming(word: "gamma", start: 5, end: 6),
            WordTiming(word: "after", start: 9, end: 10),
        ]
        let sentences = BookAlignmentRunner.assembleSentences(text: text, sourceFile: "f",
                                                               matchedRanges: ranges, transcriptWords: transcript)
        XCTAssertEqual(sentences.count, 1)
        XCTAssertEqual(sentences[0].wordStart, 1)
        XCTAssertEqual(sentences[0].wordEnd, 2)
    }

    // MARK: 📖 Bridged holes (schema 4 — the Odyssey dropped-sentence round, 2026-07-22)

    /// The Trojan War case: the aligner matched the sentences around a hole but nothing in
    /// it, while the narration clearly runs through the gap. The book sentence must be
    /// emitted with interpolated times + `bridged: true` (confidence stays honest at 0) —
    /// never silently dropped.
    func testSandwichedHoleBridgesToBookSentence() {
        let text = "Alpha beta. Gamma delta epsilon. Zeta eta."
        let ranges = [
            AlignmentCore.Result.MatchedRange(sourceFile: "f", bookWordStart: 0, bookWordEnd: 2, start: 0, end: 2),
            AlignmentCore.Result.MatchedRange(sourceFile: "f", bookWordStart: 5, bookWordEnd: 7, start: 10, end: 12),
        ]
        // 3 spoken words inside the [2, 10] window — compatible with the hole's 3 book words.
        let transcript = [
            WordTiming(word: "gamma", start: 3, end: 4),
            WordTiming(word: "delta", start: 4, end: 5),
            WordTiming(word: "epsilon", start: 5, end: 6),
        ]
        let sentences = BookAlignmentRunner.assembleSentences(text: text, sourceFile: "f",
                                                               matchedRanges: ranges, transcriptWords: transcript)
        guard sentences.count == 3 else { return XCTFail("expected 3 sentences, got \(sentences.count)") }
        let bridged = sentences[1]
        XCTAssertEqual(bridged.text, "Gamma delta epsilon.")
        XCTAssertEqual(bridged.bridged, true)
        XCTAssertEqual(bridged.confidence, 0, accuracy: 0.0001, "nothing was matched — stays honest")
        XCTAssertEqual(bridged.start, 2, accuracy: 0.001, "the window opens at prev.end")
        XCTAssertEqual(bridged.end, 10, accuracy: 0.001, "…and closes at next.start")
        XCTAssertEqual(bridged.words.count, 3, "karaoke words present (linear within the window)")
        XCTAssertEqual(bridged.wordStart, 0)
        XCTAssertEqual(bridged.wordEnd, 3, "splice covers the window's ASR words (gap-fill can't duplicate)")
        XCTAssertNil(sentences[0].bridged)
        XCTAssertNil(sentences[2].bridged)
    }

    /// A silent window means the narrator SKIPPED this text (abridged read) — inventing
    /// book text into the timeline would be a lie. The hole stays dropped.
    func testHoleWithSilentWindowStaysDropped() {
        let text = "Alpha beta. Gamma delta epsilon. Zeta eta."
        let ranges = [
            AlignmentCore.Result.MatchedRange(sourceFile: "f", bookWordStart: 0, bookWordEnd: 2, start: 0, end: 2),
            AlignmentCore.Result.MatchedRange(sourceFile: "f", bookWordStart: 5, bookWordEnd: 7, start: 10, end: 12),
        ]
        let sentences = BookAlignmentRunner.assembleSentences(text: text, sourceFile: "f",
                                                               matchedRanges: ranges, transcriptWords: [])
        XCTAssertEqual(sentences.map(\.text), ["Alpha beta.", "Zeta eta."])
    }

    /// Far more narration in the window than the hole's book words = the audio there is
    /// something ELSE (a long aside) — no bridge; the ASR gap fill owns that span.
    func testOversizedNarrationWindowDoesNotBridge() {
        let text = "Alpha beta. Gamma delta epsilon. Zeta eta."
        let ranges = [
            AlignmentCore.Result.MatchedRange(sourceFile: "f", bookWordStart: 0, bookWordEnd: 2, start: 0, end: 2),
            AlignmentCore.Result.MatchedRange(sourceFile: "f", bookWordStart: 5, bookWordEnd: 7, start: 10, end: 12),
        ]
        let transcript = (0..<8).map { WordTiming(word: "w\($0)", start: 2.5 + Double($0) * 0.8,
                                                  end: 2.5 + Double($0) * 0.8 + 0.5) }
        let sentences = BookAlignmentRunner.assembleSentences(text: text, sourceFile: "f",
                                                               matchedRanges: ranges, transcriptWords: transcript)
        XCTAssertEqual(sentences.map(\.text), ["Alpha beta.", "Zeta eta."],
                       "8 spoken vs 3 book words breaches the 2.0 ratio — no bridge")
    }

    /// A hole with no timed neighbor on one side (block head/tail) is unreached front/end
    /// matter — never bridged.
    func testLeadingHoleNeverBridges() {
        let text = "Alpha beta. Gamma delta."
        let ranges = [AlignmentCore.Result.MatchedRange(sourceFile: "f", bookWordStart: 2, bookWordEnd: 4, start: 5, end: 7)]
        let transcript = [WordTiming(word: "x", start: 1, end: 2), WordTiming(word: "y", start: 2, end: 3)]
        let sentences = BookAlignmentRunner.assembleSentences(text: text, sourceFile: "f",
                                                               matchedRanges: ranges, transcriptWords: transcript)
        XCTAssertEqual(sentences.map(\.text), ["Gamma delta."])
    }

    /// A multi-sentence hole run shares the window proportionally by word count.
    func testMultiSentenceHoleRunSharesWindowByWordCount() {
        let text = "Alpha beta. Gamma delta. One two three four. Zeta eta."
        let ranges = [
            AlignmentCore.Result.MatchedRange(sourceFile: "f", bookWordStart: 0, bookWordEnd: 2, start: 0, end: 2),
            AlignmentCore.Result.MatchedRange(sourceFile: "f", bookWordStart: 8, bookWordEnd: 10, start: 8, end: 10),
        ]
        // 6 spoken words in the [2, 8] window — matches the run's 6 book words.
        let transcript = (0..<6).map { WordTiming(word: "w\($0)", start: 2.2 + Double($0) * 0.9,
                                                  end: 2.2 + Double($0) * 0.9 + 0.6) }
        let sentences = BookAlignmentRunner.assembleSentences(text: text, sourceFile: "f",
                                                               matchedRanges: ranges, transcriptWords: transcript)
        guard sentences.count == 4 else { return XCTFail("expected 4 sentences, got \(sentences.count)") }
        // Window 6 s split 2:4 by word count → [2,4] and [4,8].
        XCTAssertEqual(sentences[1].text, "Gamma delta.")
        XCTAssertEqual(sentences[1].start, 2, accuracy: 0.001)
        XCTAssertEqual(sentences[1].end, 4, accuracy: 0.001)
        XCTAssertEqual(sentences[2].text, "One two three four.")
        XCTAssertEqual(sentences[2].start, 4, accuracy: 0.001)
        XCTAssertEqual(sentences[2].end, 8, accuracy: 0.001)
        XCTAssertEqual(sentences[1].bridged, true)
        XCTAssertEqual(sentences[2].bridged, true)
    }

    /// Schema 3: `textFile` (which ATTACHED TEXT this sentence came from, distinct from
    /// `sourceFile`, that text's own internal spine path) is stamped when passed, and stays nil
    /// (its default) when omitted — every pre-existing call site above omits it and must keep
    /// compiling/passing unchanged.
    func testTextFileStampedWhenPassed() {
        let text = "Alpha beta."
        let ranges = [AlignmentCore.Result.MatchedRange(sourceFile: "f", bookWordStart: 0, bookWordEnd: 2, start: 0, end: 2)]
        let stamped = BookAlignmentRunner.assembleSentences(text: text, sourceFile: "f", matchedRanges: ranges,
                                                             transcriptWords: [], textFile: "a.epub")
        XCTAssertEqual(stamped.first?.textFile, "a.epub")

        let unstamped = BookAlignmentRunner.assembleSentences(text: text, sourceFile: "f", matchedRanges: ranges,
                                                               transcriptWords: [])
        XCTAssertNil(unstamped.first?.textFile)
    }
}

// MARK: - mergeSentences + mergedFileAlignment (schema 3 multi-text merge)

final class MultiTextMergeTests: XCTestCase {
    private func sentence(_ textFile: String, start: TimeInterval, end: TimeInterval, confidence: Double = 1) -> AlignedSentence {
        AlignedSentence(text: "x", start: start, end: end, wordStart: 0, wordEnd: 1, confidence: confidence,
                        words: [], sourceFile: "f.xhtml", textFile: textFile)
    }

    // MARK: mergeSentences

    func testDisjointSentencesFromDifferentTextsCoexist() {
        let keep = [sentence("a.epub", start: 0, end: 10)]
        let incoming = [sentence("b.epub", start: 20, end: 30)]
        let merged = BookAlignmentRunner.mergeSentences(into: keep, adding: incoming, textRank: ["a.epub": 0, "b.epub": 1])
        XCTAssertEqual(merged.count, 2)
        XCTAssertTrue(merged.contains { $0.textFile == "a.epub" })
        XCTAssertTrue(merged.contains { $0.textFile == "b.epub" })
    }

    func testHigherConfidenceIncomingWinsCollision() {
        let keep = [sentence("a.epub", start: 0, end: 10, confidence: 0.5)]
        let incoming = [sentence("b.epub", start: 2, end: 8, confidence: 0.9)]
        let merged = BookAlignmentRunner.mergeSentences(into: keep, adding: incoming, textRank: ["a.epub": 0, "b.epub": 1])
        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged.first?.textFile, "b.epub")
    }

    func testLowerConfidenceIncomingLosesCollisionAndKeepIsUntouched() {
        let keep = [sentence("a.epub", start: 0, end: 10, confidence: 0.9)]
        let incoming = [sentence("b.epub", start: 2, end: 8, confidence: 0.5)]
        let merged = BookAlignmentRunner.mergeSentences(into: keep, adding: incoming, textRank: ["a.epub": 0, "b.epub": 1])
        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged.first?.textFile, "a.epub")
    }

    /// Tie (equal confidence) → the EARLIER attach rank wins, regardless of which side (keep vs.
    /// incoming) it's on.
    func testTiedConfidenceBreaksByEarlierAttachOrder() {
        let earlyKeep = [sentence("a.epub", start: 0, end: 10, confidence: 0.7)]
        let lateIncoming = [sentence("b.epub", start: 2, end: 8, confidence: 0.7)]
        let merged1 = BookAlignmentRunner.mergeSentences(into: earlyKeep, adding: lateIncoming,
                                                          textRank: ["a.epub": 0, "b.epub": 1])
        XCTAssertEqual(merged1.first?.textFile, "a.epub", "earlier-attached a.epub keeps its ground on a tie")

        let lateKeep = [sentence("b.epub", start: 0, end: 10, confidence: 0.7)]
        let earlyIncoming = [sentence("a.epub", start: 2, end: 8, confidence: 0.7)]
        let merged2 = BookAlignmentRunner.mergeSentences(into: lateKeep, adding: earlyIncoming,
                                                          textRank: ["a.epub": 0, "b.epub": 1])
        XCTAssertEqual(merged2.first?.textFile, "a.epub", "earlier-attached a.epub displaces b.epub on a tie")
    }

    /// One incoming sentence contesting TWO existing (non-overlapping with each other) sentences
    /// at once must win or lose ATOMICALLY — never a partial swap that blows a hole in the
    /// loser's coverage for nothing in return.
    func testWideIncomingSentenceAtomicAgainstMultipleConflicts() {
        let keep = [sentence("a.epub", start: 0, end: 10, confidence: 0.95),
                   sentence("a.epub", start: 40, end: 50, confidence: 0.3)]
        let incoming = [sentence("b.epub", start: 0, end: 50, confidence: 0.9)]
        let merged = BookAlignmentRunner.mergeSentences(into: keep, adding: incoming, textRank: ["a.epub": 0, "b.epub": 1])
        XCTAssertEqual(merged.count, 2, "incoming loses against the toughest (0.95) conflict — BOTH a.epub sentences survive untouched")
        XCTAssertTrue(merged.allSatisfy { $0.textFile == "a.epub" })
    }

    /// Regression (2026-07-23, the Odyssey verify round): collisions contest BETWEEN texts
    /// only. One text's own fresh batch routinely carries hairline TIME overlaps between
    /// adjacent sentences (the aligner's exact per-word times straddle sentence seams — real
    /// device data: "…(andra)." ends 165.8 while "He is not 'the' man…" starts 165.6). The
    /// old within-batch contest made the later same-text sentence LOSE the tie (same rank,
    /// strict-win rule) and vanish — 196 of the Odyssey's 7506 direct-matched sentences were
    /// silently eaten, including both sentences the user reported missing.
    func testSameTextSeamOverlapNeverContests() {
        let incoming = [sentence("a.epub", start: 158.9, end: 165.8),
                        sentence("a.epub", start: 165.6, end: 181.9),
                        sentence("a.epub", start: 181.9, end: 188.8)]
        let merged = BookAlignmentRunner.mergeSentences(into: [], adding: incoming, textRank: ["a.epub": 0])
        XCTAssertEqual(merged.count, 3, "same-text seam fuzz is not a collision — every sentence survives")
    }

    /// The between-text contest still applies when the OVERLAPPING existing sentence belongs
    /// to another text — same-text leniency must not leak across texts.
    func testBetweenTextOverlapStillContests() {
        let keep = [sentence("a.epub", start: 0, end: 10, confidence: 0.9)]
        let incoming = [sentence("b.epub", start: 9.9, end: 20, confidence: 0.5)]
        let merged = BookAlignmentRunner.mergeSentences(into: keep, adding: incoming, textRank: ["a.epub": 0, "b.epub": 1])
        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged.first?.textFile, "a.epub")
    }

    // MARK: mergedFileAlignment

    func testFreshMergeWithNoExisting() {
        let fa = BookAlignmentRunner.mergedFileAlignment(
            existing: nil, fileIndex: 0, textFilename: "a.epub", title: "Book A",
            verdict: .aligned, coverage: 0.8, sentences: [sentence("a.epub", start: 0, end: 10)],
            transcriptSignature: "1:1", epubSignature: "sig", textRank: ["a.epub": 0])
        XCTAssertEqual(fa.verdict, "aligned")
        XCTAssertEqual(fa.sources.count, 1)
        XCTAssertEqual(fa.sources.first?.title, "Book A")
        XCTAssertEqual(fa.sentences.count, 1)
    }

    /// Re-attaching the SAME filename replaces only its own sentences/source — a different,
    /// already-present text's contribution is untouched.
    func testReAttachSameFilenameReplacesOnlyItsOwnSentences() {
        var existing = FileAlignment(fileIndex: 0, transcriptSignature: "1:1", epubSignature: "old", verdict: "aligned")
        existing.sentences = [sentence("a.epub", start: 0, end: 10), sentence("b.epub", start: 20, end: 30)]
        existing.sources = [AlignmentSource(textFilename: "a.epub", title: "Old Title", verdict: "aligned", coverage: 0.5),
                            AlignmentSource(textFilename: "b.epub", title: "B", verdict: "aligned", coverage: 0.9)]

        let updated = BookAlignmentRunner.mergedFileAlignment(
            existing: existing, fileIndex: 0, textFilename: "a.epub", title: "New Title",
            verdict: .aligned, coverage: 0.95, sentences: [sentence("a.epub", start: 0, end: 12)],
            transcriptSignature: "2:2", epubSignature: "new", textRank: ["a.epub": 0, "b.epub": 1])

        XCTAssertEqual(updated.sources.count, 2)
        XCTAssertEqual(updated.sources.first { $0.textFilename == "a.epub" }?.title, "New Title")
        XCTAssertEqual(updated.sources.first { $0.textFilename == "a.epub" }?.coverage, 0.95)
        // b.epub's own sentence/source is completely untouched by re-attaching a.epub.
        XCTAssertTrue(updated.sentences.contains { $0.textFile == "b.epub" && $0.end == 30 })
        XCTAssertEqual(updated.sources.first { $0.textFilename == "b.epub" }?.title, "B")
        // a.epub's OLD sentence (end: 10) is gone, replaced by the fresh one (end: 12).
        XCTAssertFalse(updated.sentences.contains { $0.textFile == "a.epub" && $0.end == 10 })
        XCTAssertTrue(updated.sentences.contains { $0.textFile == "a.epub" && $0.end == 12 })
    }

    /// File-level `verdict` = best-of across sources: a second, poorly-matching text must never
    /// regress what a first, well-matching text already achieved for this file.
    func testFileVerdictIsBestOfAcrossSources() {
        var existing = FileAlignment(fileIndex: 0, transcriptSignature: "1:1", epubSignature: "x", verdict: "aligned")
        existing.sources = [AlignmentSource(textFilename: "a.epub", title: nil, verdict: "aligned", coverage: 0.8)]
        let updated = BookAlignmentRunner.mergedFileAlignment(
            existing: existing, fileIndex: 0, textFilename: "b.epub", title: nil,
            verdict: .rejected, coverage: 0.01, sentences: [],
            transcriptSignature: "1:1", epubSignature: "y", textRank: ["a.epub": 0, "b.epub": 1])
        XCTAssertEqual(updated.verdict, "aligned", "b.epub's rejection must not regress a.epub's aligned verdict")
    }
}

// MARK: - strippingText + detachedTextFields (schema 3 removal)

final class TextDetachTests: XCTestCase {
    private func sentence(_ textFile: String) -> AlignedSentence {
        AlignedSentence(text: "x", start: 0, end: 1, wordStart: 0, wordEnd: 1, confidence: 1,
                        words: [], sourceFile: "f.xhtml", textFile: textFile)
    }

    func testStripsOnlyTheNamedTextOtherTextUntouched() {
        var fa = FileAlignment(fileIndex: 0, transcriptSignature: "1:1", epubSignature: "x", verdict: "aligned")
        fa.sentences = [sentence("a.epub"), sentence("b.epub")]
        fa.sources = [AlignmentSource(textFilename: "a.epub", title: nil, verdict: "aligned", coverage: 0.5),
                     AlignmentSource(textFilename: "b.epub", title: nil, verdict: "aligned", coverage: 0.9)]
        let stripped = BookAlignmentRunner.strippingText("a.epub", from: fa)
        XCTAssertEqual(stripped.sentences.count, 1)
        XCTAssertEqual(stripped.sentences.first?.textFile, "b.epub")
        XCTAssertEqual(stripped.sources.count, 1)
        XCTAssertEqual(stripped.sources.first?.textFilename, "b.epub")
        XCTAssertEqual(stripped.verdict, "aligned", "b.epub's own verdict survives")
        XCTAssertEqual(stripped.transcriptSignature, "1:1", "still-covered file keeps its signature")
    }

    /// A file whose ONLY source was the removed text is left with zero sources — its
    /// `transcriptSignature` is cleared so a future `alignIfNeeded` doesn't think it's "fresh"
    /// with nothing in it.
    func testStrippingLastSourceClearsTranscriptSignatureAndVerdict() {
        var fa = FileAlignment(fileIndex: 0, transcriptSignature: "1:1", epubSignature: "x", verdict: "aligned")
        fa.sentences = [sentence("a.epub")]
        fa.sources = [AlignmentSource(textFilename: "a.epub", title: nil, verdict: "aligned", coverage: 0.5)]
        let stripped = BookAlignmentRunner.strippingText("a.epub", from: fa)
        XCTAssertTrue(stripped.sources.isEmpty)
        XCTAssertTrue(stripped.sentences.isEmpty)
        XCTAssertEqual(stripped.verdict, "rejected")
        XCTAssertEqual(stripped.transcriptSignature, "")
    }

    func testStrippingUninvolvedTextIsANoOp() {
        var fa = FileAlignment(fileIndex: 0, transcriptSignature: "1:1", epubSignature: "x", verdict: "aligned")
        fa.sentences = [sentence("a.epub")]
        fa.sources = [AlignmentSource(textFilename: "a.epub", title: nil, verdict: "aligned", coverage: 0.5)]
        let untouched = BookAlignmentRunner.strippingText("never-attached.epub", from: fa)
        XCTAssertEqual(untouched, fa)
    }

    func testDetachedTextFieldsFixesLegacySlotToFirstRemaining() {
        let fields = BookAlignmentRunner.detachedTextFields(removing: "b.epub", from: ["a.epub", "b.epub", "c.epub"])
        XCTAssertEqual(fields.epubFilenames, ["a.epub", "c.epub"])
        XCTAssertEqual(fields.epubFilename, "a.epub")
    }

    func testDetachedTextFieldsClearsBothWhenLastTextRemoved() {
        let fields = BookAlignmentRunner.detachedTextFields(removing: "only.epub", from: ["only.epub"])
        XCTAssertNil(fields.epubFilenames)
        XCTAssertNil(fields.epubFilename)
    }
}

// MARK: - assignChapterMarks + epubChapters (chapter derivation)

final class ChapterDerivationTests: XCTestCase {
    private func sentence(_ sourceFile: String, start: TimeInterval) -> AlignedSentence {
        AlignedSentence(text: "x", start: start, end: start + 1, wordStart: 0, wordEnd: 1,
                        confidence: 1, words: [], sourceFile: sourceFile)
    }

    func testFirstMatchWinsAcrossFiles() {
        let toc = [EPubTOCEntry(title: "Ch 1", sourceFile: "a.xhtml", fragment: nil),
                   EPubTOCEntry(title: "Ch 2", sourceFile: "b.xhtml", fragment: nil)]
        let file0 = [sentence("a.xhtml", start: 0), sentence("a.xhtml", start: 10)]
        let file1 = [sentence("b.xhtml", start: 0)]
        let marks = BookAlignmentRunner.assignChapterMarks(toc: toc, sentencesByFile: [file0, file1],
                                                           verdicts: ["aligned", "aligned"])
        XCTAssertEqual(marks[0], [ChapterMark(title: "Ch 1", sentenceIndex: 0)])
        XCTAssertEqual(marks[1], [ChapterMark(title: "Ch 2", sentenceIndex: 0)])
    }

    func testSkipsTocEntryWithNoAlignedSentenceAnywhere() {
        let toc = [EPubTOCEntry(title: "Missing", sourceFile: "nope.xhtml", fragment: nil),
                   EPubTOCEntry(title: "Found", sourceFile: "a.xhtml", fragment: nil)]
        let marks = BookAlignmentRunner.assignChapterMarks(toc: toc, sentencesByFile: [[sentence("a.xhtml", start: 5)]],
                                                           verdicts: ["aligned"])
        XCTAssertEqual(marks[0], [ChapterMark(title: "Found", sentenceIndex: 0)])
    }

    /// Regression (2026-07-22 device catch, the phantom-chapters bug): a REJECTED file's
    /// spurious matched sentences must never claim a TOC entry — on the real Steal pair,
    /// 6 front-matter entries the aligned file couldn't claim were grabbed by a rejected
    /// trilogy-sibling file, planting real-titled chapters at junk times.
    /// Round-3 device catch: the sheet's bar sprinkled confetti across the whole book —
    /// `textSummary` counted a text's sentences from files whose verdict for that text
    /// was REJECTED (spurious matches). Spans/coverage are aligned-files-only.
    @MainActor func testTextSummaryExcludesRejectedFilesSentences() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ts_\(UUID().uuidString)", isDirectory: true)
        let library = AudiobookLibraryStore(directory: dir)
        var book = Audiobook(files: ["a.mp3", "b.mp3"], fileDurations: [100, 100],
                             title: "T", author: "A", duration: 200)
        book.epubFilenames = ["steal.epub"]
        library.add(book)

        let store = BookAlignmentStore(directory: dir)
        var fa0 = FileAlignment(fileIndex: 0, transcriptSignature: "", epubSignature: "", verdict: "aligned")
        fa0.sources = [AlignmentSource(textFilename: "steal.epub", title: "Steal", verdict: "aligned", coverage: 0.9)]
        fa0.sentences = [AlignedSentence(text: "x", start: 0, end: 50, wordStart: 0, wordEnd: 1,
                                         confidence: 1, words: [], sourceFile: "c1", textFile: "steal.epub")]
        try store.save(fa0, bookID: book.id)
        var fa1 = FileAlignment(fileIndex: 1, transcriptSignature: "", epubSignature: "", verdict: "rejected")
        fa1.sources = [AlignmentSource(textFilename: "steal.epub", title: "Steal", verdict: "rejected", coverage: 0.05)]
        fa1.sentences = [AlignedSentence(text: "junk", start: 10, end: 20, wordStart: 0, wordEnd: 1,
                                         confidence: 0.6, words: [], sourceFile: "c9", textFile: "steal.epub")]
        try store.save(fa1, bookID: book.id)

        let summary = BookAlignmentRunner.textSummary(bookID: book.id, library: library)
        let per = try XCTUnwrap(summary?.perText.first)
        XCTAssertEqual(per.fileNumbers, [1])
        XCTAssertEqual(per.coveredSeconds, 50, accuracy: 0.01, "rejected file's junk must not count")
        XCTAssertTrue(per.spans.allSatisfy { $0.upperBound <= 100 }, "no span may reach into the rejected file")
    }

    func testRejectedFileNeverClaimsTocEntries() {
        let toc = [EPubTOCEntry(title: "Copyright", sourceFile: "fm.xhtml", fragment: nil)]
        let rejectedOnly = BookAlignmentRunner.assignChapterMarks(
            toc: toc, sentencesByFile: [[], [sentence("fm.xhtml", start: 7)]],
            verdicts: ["aligned", "rejected"])
        XCTAssertEqual(rejectedOnly, [[], []], "the rejected file's sentence must not claim the entry")
    }

    func testEpubChaptersIgnoresRejectedFileAlignments() {
        var rejected = FileAlignment(fileIndex: 0, transcriptSignature: "", epubSignature: "",
                                     verdict: "rejected")
        rejected.sentences = [sentence("fm.xhtml", start: 7)]
        rejected.chapterMarks = [ChapterMark(title: "Phantom", sentenceIndex: 0)]   // stale v1-era mark
        XCTAssertEqual(BookAlignmentRunner.epubChapters(from: [rejected], fileStartTimes: [0],
                                                        bookDuration: 100), [],
                       "marks stored on a rejected sidecar must be inert")
    }

    func testEmptyTocProducesNoMarks() {
        let marks = BookAlignmentRunner.assignChapterMarks(toc: [], sentencesByFile: [[sentence("a.xhtml", start: 0)]],
                                                           verdicts: ["aligned"])
        XCTAssertEqual(marks, [[]])
    }

    func testEpubChaptersGlobalOffsetsAndDurationFixup() {
        var fa0 = FileAlignment(fileIndex: 0, transcriptSignature: "", epubSignature: "", verdict: "aligned")
        fa0.sentences = [sentence("a.xhtml", start: 2)]
        fa0.chapterMarks = [ChapterMark(title: "Ch 1", sentenceIndex: 0)]
        var fa1 = FileAlignment(fileIndex: 1, transcriptSignature: "", epubSignature: "", verdict: "aligned")
        fa1.sentences = [sentence("b.xhtml", start: 3)]
        fa1.chapterMarks = [ChapterMark(title: "Ch 2", sentenceIndex: 0)]

        let chapters = BookAlignmentRunner.epubChapters(from: [fa0, fa1], fileStartTimes: [0, 100], bookDuration: 200)
        XCTAssertEqual(chapters.count, 2)
        XCTAssertEqual(chapters[0].title, "Ch 1")
        XCTAssertEqual(chapters[0].start, 2, accuracy: 0.001)
        XCTAssertEqual(chapters[0].duration, 101, accuracy: 0.001)   // up to Ch 2's global start (103)
        XCTAssertEqual(chapters[1].title, "Ch 2")
        XCTAssertEqual(chapters[1].start, 103, accuracy: 0.001)
        XCTAssertEqual(chapters[1].duration, 97, accuracy: 0.001)    // 200 - 103
    }

    /// Partial-match merge (Tuur's trilogy, 2026-07-22 + the no-bad-info rule): the ePub
    /// TOC wins only INSIDE aligned files; transcript-detected chapters (and separators)
    /// OUTSIDE those spans survive — books 2–3 of a trilogy must not lose their chapters.
    func testPartialMatchKeepsDetectedChaptersOutsideAlignedSpan() {
        var fa0 = FileAlignment(fileIndex: 0, transcriptSignature: "", epubSignature: "", verdict: "aligned")
        fa0.sentences = [sentence("a.xhtml", start: 2)]
        fa0.chapterMarks = [ChapterMark(title: "Real Ch 1", sentenceIndex: 0)]
        let detected = [
            AudiobookChapter(title: "Old Detected In File 0", start: 30, duration: 0),   // inside aligned span → dropped
            AudiobookChapter(title: "Book 2", start: 100, duration: 0, isSeparator: true),
            AudiobookChapter(title: "Book 2 Ch 1", start: 105, duration: 0),
        ]
        let chapters = BookAlignmentRunner.epubChapters(
            from: [fa0, nil], fileStartTimes: [0, 100], bookDuration: 200,
            detected: detected, fileDurations: [100, 100])
        XCTAssertEqual(chapters.map(\.title), ["Real Ch 1", "Book 2", "Book 2 Ch 1"])
        // Guarded subscripts — a bare chapters[2] here once crashed the whole test
        // RUNNER (mass-killing 255 unrelated tests) when the count regressed.
        guard chapters.count == 3 else { return XCTFail("expected 3 chapters, got \(chapters.count)") }
        XCTAssertEqual(chapters[1].isSeparator, true)
        XCTAssertEqual(chapters[2].start, 105, accuracy: 0.001)
    }

    func testNilFileAlignmentSkipped() {
        XCTAssertEqual(BookAlignmentRunner.epubChapters(from: [nil], fileStartTimes: [0], bookDuration: 10), [])
    }

    func testOutOfRangeSentenceIndexSkipped() {
        var fa = FileAlignment(fileIndex: 0, transcriptSignature: "", epubSignature: "", verdict: "aligned")
        fa.chapterMarks = [ChapterMark(title: "Ghost", sentenceIndex: 0)]   // no sentence 0 exists
        XCTAssertEqual(BookAlignmentRunner.epubChapters(from: [fa], fileStartTimes: [0], bookDuration: 10), [])
    }
}

// MARK: - perTextChapterMarks (schema 3 — per-text marks, remapped + unioned across texts)

final class PerTextChapterMarksTests: XCTestCase {
    private func sentence(_ textFile: String, _ sourceFile: String, start: TimeInterval) -> AlignedSentence {
        AlignedSentence(text: "x", start: start, end: start + 1, wordStart: 0, wordEnd: 1, confidence: 1,
                        words: [], sourceFile: sourceFile, textFile: textFile)
    }

    /// `assignChapterMarks` (called internally against the FILTERED, text-only subarray) reports
    /// an index LOCAL to that subarray — `perTextChapterMarks` must remap it back to the index
    /// into the FULL, multi-text `fullSentencesByFile` array (what `ChapterMark.sentenceIndex` is
    /// always consumed against downstream, e.g. `epubChapters`).
    func testMarksRemappedToFullArrayIndices() {
        let full = [[sentence("other.epub", "z.xhtml", start: 0), sentence("a.epub", "ch1.xhtml", start: 5)]]
        let toc = [EPubTOCEntry(title: "Ch 1", sourceFile: "ch1.xhtml", fragment: nil)]
        let marks = BookAlignmentRunner.perTextChapterMarks(forText: "a.epub", toc: toc,
                                                             fullSentencesByFile: full, sourceVerdicts: ["aligned"])
        XCTAssertEqual(marks, [[ChapterMark(title: "Ch 1", sentenceIndex: 1)]], "index 1 in the FULL array, not 0")
    }

    /// Gated on THIS TEXT's own per-file (source) verdict, not the file's merged best-of — a
    /// text that came back rejected against a file must never claim that file's TOC entries even
    /// if another, better text made the file's OVERALL verdict "aligned" (phantom-chapters
    /// protection, generalized to multi-text).
    func testRejectedSourceVerdictNeverClaimsATocEntry() {
        let full = [[sentence("a.epub", "ch1.xhtml", start: 0)]]
        let toc = [EPubTOCEntry(title: "Ch 1", sourceFile: "ch1.xhtml", fragment: nil)]
        let marks = BookAlignmentRunner.perTextChapterMarks(forText: "a.epub", toc: toc,
                                                             fullSentencesByFile: full, sourceVerdicts: ["rejected"])
        XCTAssertEqual(marks, [[]])
    }

    /// Two different texts' marks, computed separately and concatenated (what `reconcileChapters`
    /// does per file) — remapped to different, non-colliding indices in the SAME full array.
    func testTwoTextsProduceNonCollidingIndicesInTheSameFile() {
        let full = [[sentence("a.epub", "a1.xhtml", start: 0), sentence("b.epub", "b1.xhtml", start: 10)]]
        let aMarks = BookAlignmentRunner.perTextChapterMarks(
            forText: "a.epub", toc: [EPubTOCEntry(title: "Ch 1", sourceFile: "a1.xhtml", fragment: nil)],
            fullSentencesByFile: full, sourceVerdicts: ["aligned"])
        let bMarks = BookAlignmentRunner.perTextChapterMarks(
            forText: "b.epub", toc: [EPubTOCEntry(title: "Ch 2", sourceFile: "b1.xhtml", fragment: nil)],
            fullSentencesByFile: full, sourceVerdicts: ["aligned"])
        XCTAssertEqual(aMarks, [[ChapterMark(title: "Ch 1", sentenceIndex: 0)]])
        XCTAssertEqual(bMarks, [[ChapterMark(title: "Ch 2", sentenceIndex: 1)]])
        // Concatenating the two never collides — each names a different sentence.
        let union = zip(aMarks, bMarks).map { $0 + $1 }
        XCTAssertEqual(union, [[ChapterMark(title: "Ch 1", sentenceIndex: 0), ChapterMark(title: "Ch 2", sentenceIndex: 1)]])
    }
}

// MARK: - parseBookFile: `.txt` single-block path (no ZIPFoundation)

final class ParseBookFileTests: XCTestCase {
    func testPlainTextBecomesSingleBlockBook() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("book_\(UUID().uuidString).txt")
        let text = "Once upon a time, in a land far away."
        try text.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let book = try BookAlignmentRunner.parseBookFile(at: url)
        XCTAssertEqual(book.blocks.count, 1)
        XCTAssertEqual(book.blocks[0].text, text)
        XCTAssertEqual(book.blocks[0].sourceFile, url.lastPathComponent)
        XCTAssertTrue(book.toc.isEmpty)
        XCTAssertEqual(book.drm, .none)
    }

    func testExtensionlessFileAlsoTakesThePlainTextPath() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("book_\(UUID().uuidString)")
        try "Just words.".write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let book = try BookAlignmentRunner.parseBookFile(at: url)
        XCTAssertEqual(book.blocks.count, 1)
        XCTAssertEqual(book.blocks[0].text, "Just words.")
    }
}

// MARK: - textSummary (📖 multi-text "Book text" sheet data)

final class BookTextSummaryTests: XCTestCase {
    @MainActor
    private func makeLibrary() -> AudiobookLibraryStore {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("textsummary_\(UUID().uuidString)", isDirectory: true)
        return AudiobookLibraryStore(directory: dir)
    }

    private func sentence(_ textFile: String, start: TimeInterval, end: TimeInterval) -> AlignedSentence {
        AlignedSentence(text: "x", start: start, end: end, wordStart: 0, wordEnd: 1, confidence: 1,
                        words: [], sourceFile: "f.xhtml", textFile: textFile)
    }

    @MainActor
    func testPerTextSpansCoverageFileNumbersAndTitles() throws {
        let library = makeLibrary()
        var book = Audiobook(files: ["f0.mp3", "f1.mp3"], fileDurations: [100, 100],
                             title: "T", author: "A", duration: 200)
        book.epubFilenames = ["a.epub", "b.epub"]
        library.add(book)

        let store = BookAlignmentStore(directory: library.directory)
        var fa0 = FileAlignment(fileIndex: 0, transcriptSignature: "", epubSignature: "", verdict: "aligned")
        fa0.sources = [AlignmentSource(textFilename: "a.epub", title: "Book A", verdict: "aligned", coverage: 0.9)]
        // 5s gap between the two — within the 30s gap-bridge threshold.
        fa0.sentences = [sentence("a.epub", start: 0, end: 10), sentence("a.epub", start: 15, end: 20)]
        try store.save(fa0, bookID: book.id)

        var fa1 = FileAlignment(fileIndex: 1, transcriptSignature: "", epubSignature: "", verdict: "aligned")
        fa1.sources = [AlignmentSource(textFilename: "b.epub", title: "Book B", verdict: "aligned", coverage: 0.8)]
        fa1.sentences = [sentence("b.epub", start: 0, end: 30)]
        try store.save(fa1, bookID: book.id)

        let summary = try XCTUnwrap(BookAlignmentRunner.textSummary(bookID: book.id, library: library))
        XCTAssertEqual(summary.bookDuration, 200)
        XCTAssertEqual(summary.perText.count, 2)

        let a = summary.perText[0]
        XCTAssertEqual(a.filename, "a.epub")
        XCTAssertEqual(a.title, "Book A")
        XCTAssertEqual(a.spans, [0...20], "the 5s gap between the two a.epub sentences is bridged")
        XCTAssertEqual(a.coveredSeconds, 20, accuracy: 0.001, "sum of the (bridged) spans, not raw sentence seconds")
        XCTAssertEqual(a.fileNumbers, [1])

        let b = summary.perText[1]
        XCTAssertEqual(b.filename, "b.epub")
        XCTAssertEqual(b.title, "Book B")
        XCTAssertEqual(b.spans, [100...130], "GLOBAL time — file 1 starts at 100")
        XCTAssertEqual(b.fileNumbers, [2])

        XCTAssertEqual(summary.totalCoveredSeconds, 20 + 30, accuracy: 0.001)
    }

    @MainActor
    func testGapOver30sIsNotBridged() throws {
        let library = makeLibrary()
        var book = Audiobook(files: ["f0.mp3"], fileDurations: [200], title: "T", author: "A", duration: 200)
        book.epubFilenames = ["a.epub"]
        library.add(book)

        let store = BookAlignmentStore(directory: library.directory)
        var fa0 = FileAlignment(fileIndex: 0, transcriptSignature: "", epubSignature: "", verdict: "aligned")
        fa0.sources = [AlignmentSource(textFilename: "a.epub", title: nil, verdict: "aligned", coverage: 0.5)]
        fa0.sentences = [sentence("a.epub", start: 0, end: 10), sentence("a.epub", start: 90, end: 100)]   // 80s gap
        try store.save(fa0, bookID: book.id)

        let summary = try XCTUnwrap(BookAlignmentRunner.textSummary(bookID: book.id, library: library))
        XCTAssertEqual(summary.perText.first?.spans, [0...10, 90...100])
        XCTAssertNil(summary.perText.first?.title, "no dc:title stored → caller falls back to the filename")
    }

    @MainActor
    func testFileNumbersOnlyCountAlignedVerdictSources() throws {
        let library = makeLibrary()
        var book = Audiobook(files: ["f0.mp3", "f1.mp3"], fileDurations: [100, 100],
                             title: "T", author: "A", duration: 200)
        book.epubFilenames = ["a.epub"]
        library.add(book)

        let store = BookAlignmentStore(directory: library.directory)
        var fa0 = FileAlignment(fileIndex: 0, transcriptSignature: "", epubSignature: "", verdict: "aligned")
        fa0.sources = [AlignmentSource(textFilename: "a.epub", title: nil, verdict: "aligned", coverage: 0.9)]
        try store.save(fa0, bookID: book.id)
        var fa1 = FileAlignment(fileIndex: 1, transcriptSignature: "", epubSignature: "", verdict: "rejected")
        fa1.sources = [AlignmentSource(textFilename: "a.epub", title: nil, verdict: "rejected", coverage: 0.01)]
        try store.save(fa1, bookID: book.id)

        let summary = try XCTUnwrap(BookAlignmentRunner.textSummary(bookID: book.id, library: library))
        XCTAssertEqual(summary.perText.first?.fileNumbers, [1], "file 2's rejected source doesn't count")
    }

    @MainActor
    func testNoAttachedTextReturnsNil() {
        let library = makeLibrary()
        let book = Audiobook(files: ["f0.mp3"], fileDurations: [10], title: "T", author: "A", duration: 10)
        library.add(book)
        XCTAssertNil(BookAlignmentRunner.textSummary(bookID: book.id, library: library))
    }

    @MainActor
    func testMissingBookReturnsNil() {
        XCTAssertNil(BookAlignmentRunner.textSummary(bookID: UUID(), library: makeLibrary()))
    }
}

// MARK: - cloudSignaturePart (CloudKit change-signature stability)

final class CloudSignaturePartTests: XCTestCase {
    /// Schema 3: gains a 4th `:<textCount>` field (`sources.count`) — the old three keep their
    /// exact prefix shape.
    func testFormat() {
        var fa = FileAlignment(fileIndex: 2, transcriptSignature: "x", epubSignature: "y", verdict: "aligned")
        fa.sentences = [
            AlignedSentence(text: "a", start: 0, end: 1, wordStart: 0, wordEnd: 1, confidence: 1, words: [], sourceFile: nil),
            AlignedSentence(text: "b", start: 1, end: 2, wordStart: 1, wordEnd: 2, confidence: 1, words: [], sourceFile: nil),
        ]
        fa.sources = [AlignmentSource(textFilename: "a.epub", title: nil, verdict: "aligned", coverage: 0.9)]
        XCTAssertEqual(fa.cloudSignaturePart(), "2:aligned:2:1")
    }

    func testStableForIdenticalContent() {
        let fa = FileAlignment(fileIndex: 0, transcriptSignature: "", epubSignature: "", verdict: "partial")
        XCTAssertEqual(fa.cloudSignaturePart(), fa.cloudSignaturePart())
    }

    func testChangesWithSentenceCount() {
        var fa = FileAlignment(fileIndex: 0, transcriptSignature: "", epubSignature: "", verdict: "partial")
        let before = fa.cloudSignaturePart()
        fa.sentences.append(AlignedSentence(text: "x", start: 0, end: 1, wordStart: 0, wordEnd: 1,
                                            confidence: 1, words: [], sourceFile: nil))
        XCTAssertNotEqual(before, fa.cloudSignaturePart())
    }

    func testChangesWithVerdict() {
        var fa = FileAlignment(fileIndex: 0, transcriptSignature: "", epubSignature: "", verdict: "partial")
        let before = fa.cloudSignaturePart()
        fa.verdict = "aligned"
        XCTAssertNotEqual(before, fa.cloudSignaturePart())
    }

    /// Schema 3: the NEW dimension — adding a second attached text's source entry changes the
    /// signature even when `verdict`/`sentences.count` happen to stay the same.
    func testChangesWithTextCount() {
        var fa = FileAlignment(fileIndex: 0, transcriptSignature: "", epubSignature: "", verdict: "partial")
        fa.sources = [AlignmentSource(textFilename: "a.epub", title: nil, verdict: "partial", coverage: 0.2)]
        let before = fa.cloudSignaturePart()
        fa.sources.append(AlignmentSource(textFilename: "b.epub", title: nil, verdict: "rejected", coverage: 0.0))
        XCTAssertNotEqual(before, fa.cloudSignaturePart())
    }
}

// MARK: - orphanedAttachedTexts (re-adoption after the attach fields were lost)

/// 2026-07-22 Odyssey report: pre-persistence-fix builds forgot the attachment on relaunch
/// while the text file + sidecars stayed in the book folder. `alignIfNeeded` re-adopts from
/// disk — this pins what counts as an orphaned attached text.
final class OrphanedAttachedTextsTests: XCTestCase {
    private func makeFolder(files: [String]) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("orphan_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for f in files {
            try Data("x".utf8).write(to: dir.appendingPathComponent(f))
        }
        return dir
    }

    func testFindsEpubAndTxtButNeverAudioSidecarsOrCover() throws {
        let dir = try makeFolder(files: [
            "odyssey.epub", "notes.txt", "book.m4b", "cover.jpg",
            "transcript_f0.json", "alignment_f0.json",
        ])
        defer { try? FileManager.default.removeItem(at: dir) }
        XCTAssertEqual(BookAlignmentRunner.orphanedAttachedTexts(inFolder: dir, audioFiles: ["book.m4b"]),
                       ["notes.txt", "odyssey.epub"], "sorted; only attachable text types")
    }

    func testAudioFilesWithTextExtensionsAreExcluded() throws {
        // A (pathological) book whose AUDIO list claims a .txt name must not re-adopt it.
        let dir = try makeFolder(files: ["weird.txt", "real.epub"])
        defer { try? FileManager.default.removeItem(at: dir) }
        XCTAssertEqual(BookAlignmentRunner.orphanedAttachedTexts(inFolder: dir, audioFiles: ["weird.txt"]),
                       ["real.epub"])
    }

    func testMissingFolderYieldsNothing() {
        let gone = FileManager.default.temporaryDirectory
            .appendingPathComponent("orphan_missing_\(UUID().uuidString)", isDirectory: true)
        XCTAssertEqual(BookAlignmentRunner.orphanedAttachedTexts(inFolder: gone, audioFiles: []), [])
    }
}
