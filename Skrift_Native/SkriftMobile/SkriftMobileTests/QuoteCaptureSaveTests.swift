import XCTest
@testable import SkriftMobile

/// `MemoSaver.saveQuoteCapture` — the C1 transcript shape (blockquote quote at
/// the top, ramble appended below a blank line) and the C2 book metadata
/// riding the existing metadata JSON.
final class QuoteCaptureSaveTests: XCTestCase {

    @MainActor
    private func makeSaver(repo: NotesRepository, sidecarDir: URL, transcriber: any Transcribing = SeededTranscriber(text: "unused")) -> MemoSaver {
        MemoSaver(
            repository: repo,
            transcriber: transcriber,
            wordTimings: WordTimingsStore(directory: sidecarDir),
            metadataProvider: MockMetadataService()
        )
    }

    private func tempAudioFile() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("quote_\(UUID().uuidString).m4a")
        FileManager.default.createFile(atPath: url.path, contents: Data("QUOTE-AUDIO".utf8))
        return url
    }

    @MainActor
    func testSaveQuoteCaptureCreatesC1MemoWithC2Metadata() throws {
        let repo = NotesRepository(inMemory: true)
        let sidecarDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("wt_\(UUID().uuidString)", isDirectory: true)
        let saver = makeSaver(repo: repo, sidecarDir: sidecarDir)
        let temp = tempAudioFile()
        let capturedAt = Date(timeIntervalSince1970: 1_760_000_000)
        let timings = [WordTiming(word: "Optimism", start: 0, end: 0.5)]

        let id = try XCTUnwrap(saver.saveQuoteCapture(
            audioTempURL: temp,
            quote: "Optimism is a stance.",
            duration: 33,
            wordTimings: timings,
            bookTitle: "The Beginning of Infinity",
            bookAuthor: "David Deutsch",
            bookChapter: "4",
            recordedAt: capturedAt
        ))

        let memo = try XCTUnwrap(repo.memo(id: id))
        // C1: blockquote at the top, no [[..]], no attribution line.
        XCTAssertEqual(memo.transcript, "> Optimism is a stance.")
        XCTAssertEqual(memo.transcriptStatus, .done)
        XCTAssertTrue(memo.transcriptUserEdited, "Mac must trust the formatted transcript verbatim")
        XCTAssertEqual(memo.duration, 33)
        XCTAssertEqual(memo.recordedAt.timeIntervalSince1970,
                       capturedAt.timeIntervalSince1970, accuracy: 0.001)
        XCTAssertEqual(memo.audioFilename, "memo_\(id.uuidString).m4a")
        XCTAssertEqual(memo.significance, 0, "unrated → the Mac skips it until the circles are set")

        // C2: book fields ride MemoMetadata.
        XCTAssertEqual(memo.metadata?.bookTitle, "The Beginning of Infinity")
        XCTAssertEqual(memo.metadata?.bookAuthor, "David Deutsch")
        XCTAssertEqual(memo.metadata?.bookChapter, "4")

        // The temp audio moved into recordings; the karaoke sidecar landed.
        XCTAssertFalse(FileManager.default.fileExists(atPath: temp.path))
        let dest = AppPaths.recordingsDirectory.appendingPathComponent(memo.audioFilename)
        XCTAssertTrue(FileManager.default.fileExists(atPath: dest.path))
        XCTAssertEqual(WordTimingsStore(directory: sidecarDir).load(for: id), timings)

        repo.permanentlyDelete(memo)   // clean the shared recordings dir
    }

    @MainActor
    func testRambleAppendsBelowQuotePerC1() async throws {
        let repo = NotesRepository(inMemory: true)
        let sidecarDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("wt_\(UUID().uuidString)", isDirectory: true)
        var saver = makeSaver(repo: repo, sidecarDir: sidecarDir,
                              transcriber: SeededTranscriber(text: "My take: failures are input."))
        saver.appendRetryDelays = [0]

        let id = try XCTUnwrap(saver.saveQuoteCapture(
            audioTempURL: tempAudioFile(),
            quote: "Optimism is a stance.",
            duration: 33,
            bookTitle: "The Beginning of Infinity",
            bookAuthor: "David Deutsch",
            bookChapter: "4"
        ))

        // The ramble rides the ordinary append flow (RecordView(appendTo:)).
        let ramble = FileManager.default.temporaryDirectory
            .appendingPathComponent("ramble_\(UUID().uuidString).m4a")
        FileManager.default.createFile(atPath: ramble.path, contents: Data("RAMBLE".utf8))
        await saver.appendRecordingAsync(to: id, tempURL: ramble, duration: 12)

        let memo = try XCTUnwrap(repo.memo(id: id))
        XCTAssertEqual(
            memo.transcript,
            "> Optimism is a stance.\n\nMy take: failures are input.",
            "C1: quote block at the top, blank line, then the ramble"
        )
        XCTAssertTrue(memo.transcriptUserEdited)
        // Book metadata survives the append untouched.
        XCTAssertEqual(memo.metadata?.bookTitle, "The Beginning of Infinity")

        repo.permanentlyDelete(memo)
    }

    @MainActor
    func testEmptyQuoteRefusesToSave() {
        let repo = NotesRepository(inMemory: true)
        let saver = makeSaver(repo: repo, sidecarDir: FileManager.default.temporaryDirectory)
        let id = saver.saveQuoteCapture(
            audioTempURL: tempAudioFile(),
            quote: "   ",
            duration: 5,
            bookTitle: nil, bookAuthor: nil, bookChapter: nil
        )
        XCTAssertNil(id)
        XCTAssertTrue(repo.allMemos().isEmpty)
    }

    // MARK: - Trim persistence math (no audio export — pure helper logic)

    /// `isUnchangedTrim` + the transcript/timing-rebase path used by
    /// `applyTrimIfNeeded` in `CaptureSheetView`. These are pure functions
    /// accessible from the test target so we can verify the data contract
    /// without spinning up AVAssetExportSession.

    func testIsUnchangedTrimNoOpWhenFlagsMatchInitial() {
        let s0 = BufferSentence(text: "Prelude.", start: 0, end: 1, words: [], isInInitialSpan: false)
        let s1 = BufferSentence(text: "Quote.", start: 1, end: 2, words: [], isInInitialSpan: true)
        let flags = [false, true]
        XCTAssertTrue(QuoteCaptureProcessor.isUnchangedTrim(included: flags, sentences: [s0, s1]),
                      "flags equal the initial span \u{2014} must be a no-op")
    }

    func testIsUnchangedTrimDetectsChange() {
        let s0 = BufferSentence(text: "Prelude.", start: 0, end: 1, words: [], isInInitialSpan: false)
        let s1 = BufferSentence(text: "Quote.", start: 1, end: 2, words: [], isInInitialSpan: true)
        XCTAssertFalse(QuoteCaptureProcessor.isUnchangedTrim(included: [true, true], sentences: [s0, s1]),
                       "user added the context sentence \u{2014} must detect the change")
        XCTAssertFalse(QuoteCaptureProcessor.isUnchangedTrim(included: [false, false], sentences: [s0, s1]),
                       "user dropped the included sentence \u{2014} must detect the change")
    }

    /// Verify the full trim-rebase data contract:
    /// - active sentences derive the correct spanStart and spanEnd
    /// - blockquote transcript is formed from the included sentence texts
    /// - word timings are rebased to t = 0 of the new audio
    func testTrimRebaseDataContract() {
        // Two sentences; user wants only sentence 1 (trim context sentence 0).
        let s0words = [WordTiming(word: "Prelude.", start: 0.0, end: 0.8)]
        let s1words = [WordTiming(word: "Optimism", start: 1.0, end: 1.4),
                       WordTiming(word: "wins.", start: 1.5, end: 1.9)]
        let s0 = BufferSentence(text: "Prelude.", start: 0.0, end: 0.8, words: s0words, isInInitialSpan: false)
        let s1 = BufferSentence(text: "Optimism wins.", start: 1.0, end: 1.9, words: s1words, isInInitialSpan: true)

        let included = [false, true]
        let active = zip([s0, s1], included).filter(\.1).map(\.0)

        // Span bounds.
        let spanStart = active[0].start
        let spanEnd   = active[active.count - 1].end
        XCTAssertEqual(spanStart, 1.0, accuracy: 0.001)
        XCTAssertEqual(spanEnd,   1.9, accuracy: 0.001)
        XCTAssertEqual(spanEnd - spanStart, 0.9, accuracy: 0.001, "trim duration")

        // Transcript.
        let joined = active.map(\.text).joined(separator: " ")
        XCTAssertEqual(QuoteFormatting.blockquote(joined), "> Optimism wins.")

        // Timing rebase.
        let allWords = active.flatMap(\.words)
        let rebased = allWords.map {
            WordTiming(word: $0.word,
                       start: max(0, $0.start - spanStart),
                       end:   max(0, $0.end   - spanStart))
        }
        XCTAssertEqual(rebased.count, 2)
        XCTAssertEqual(rebased[0].word, "Optimism")
        XCTAssertEqual(rebased[0].start, 0.0, accuracy: 0.001, "first word must start at t=0")
        XCTAssertEqual(rebased[1].word, "wins.")
        XCTAssertEqual(rebased[1].start, 0.5, accuracy: 0.001)
        XCTAssertEqual(rebased[1].end,   0.9, accuracy: 0.001)
    }

    /// Verify that a trim that adds a context sentence BEFORE the initial snap
    /// correctly anchors its span at the earlier sentence start.
    func testTrimExpandToContextSentence() {
        let s0words = [WordTiming(word: "Context.", start: 0.0, end: 0.7)]
        let s1words = [WordTiming(word: "Quote.", start: 1.0, end: 1.5)]
        let s0 = BufferSentence(text: "Context.", start: 0.0, end: 0.7, words: s0words, isInInitialSpan: false)
        let s1 = BufferSentence(text: "Quote.", start: 1.0, end: 1.5, words: s1words, isInInitialSpan: true)

        let active = [s0, s1]   // user included both
        let spanStart = active[0].start   // 0.0
        let spanEnd   = active[active.count - 1].end   // 1.5

        // Duration spans both sentences (including the gap between them).
        XCTAssertEqual(spanEnd - spanStart, 1.5, accuracy: 0.001)

        // Rebased first word at t=0.
        let allWords = active.flatMap(\.words)
        let rebased = allWords.map {
            WordTiming(word: $0.word,
                       start: max(0, $0.start - spanStart),
                       end:   max(0, $0.end   - spanStart))
        }
        XCTAssertEqual(rebased[0].start, 0.0, accuracy: 0.001)
        XCTAssertEqual(rebased[1].start, 1.0, accuracy: 0.001, "second sentence starts 1.0 s in the expanded audio")
    }
}
