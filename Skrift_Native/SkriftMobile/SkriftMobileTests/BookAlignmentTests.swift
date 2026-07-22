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
        let marks = BookAlignmentRunner.assignChapterMarks(toc: toc, sentencesByFile: [file0, file1])
        XCTAssertEqual(marks[0], [ChapterMark(title: "Ch 1", sentenceIndex: 0)])
        XCTAssertEqual(marks[1], [ChapterMark(title: "Ch 2", sentenceIndex: 0)])
    }

    func testSkipsTocEntryWithNoAlignedSentenceAnywhere() {
        let toc = [EPubTOCEntry(title: "Missing", sourceFile: "nope.xhtml", fragment: nil),
                   EPubTOCEntry(title: "Found", sourceFile: "a.xhtml", fragment: nil)]
        let marks = BookAlignmentRunner.assignChapterMarks(toc: toc, sentencesByFile: [[sentence("a.xhtml", start: 5)]])
        XCTAssertEqual(marks[0], [ChapterMark(title: "Found", sentenceIndex: 0)])
    }

    func testEmptyTocProducesNoMarks() {
        let marks = BookAlignmentRunner.assignChapterMarks(toc: [], sentencesByFile: [[sentence("a.xhtml", start: 0)]])
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

    func testNilFileAlignmentSkipped() {
        XCTAssertEqual(BookAlignmentRunner.epubChapters(from: [nil], fileStartTimes: [0], bookDuration: 10), [])
    }

    func testOutOfRangeSentenceIndexSkipped() {
        var fa = FileAlignment(fileIndex: 0, transcriptSignature: "", epubSignature: "", verdict: "aligned")
        fa.chapterMarks = [ChapterMark(title: "Ghost", sentenceIndex: 0)]   // no sentence 0 exists
        XCTAssertEqual(BookAlignmentRunner.epubChapters(from: [fa], fileStartTimes: [0], bookDuration: 10), [])
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

// MARK: - cloudSignaturePart (CloudKit change-signature stability)

final class CloudSignaturePartTests: XCTestCase {
    func testFormat() {
        var fa = FileAlignment(fileIndex: 2, transcriptSignature: "x", epubSignature: "y", verdict: "aligned")
        fa.sentences = [
            AlignedSentence(text: "a", start: 0, end: 1, wordStart: 0, wordEnd: 1, confidence: 1, words: [], sourceFile: nil),
            AlignedSentence(text: "b", start: 1, end: 2, wordStart: 1, wordEnd: 2, confidence: 1, words: [], sourceFile: nil),
        ]
        XCTAssertEqual(fa.cloudSignaturePart(), "2:aligned:2")
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
}
