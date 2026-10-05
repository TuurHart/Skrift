import XCTest
import NaturalLanguage
@testable import SkriftMobile

/// Q317: the Books tab and the player stop decoding the library and the sidecars on the
/// main thread. Counts are computed once per memo-set version (and equal the old per-row
/// counts); the transcript/alignment sidecar decode runs off the main actor; covers are
/// downsampled; the sentence-start scan is the old answer without the O(n^2).
@MainActor
final class BookNotesCountCacheTests: XCTestCase {

    private let bookA = UUID()
    private let bookB = UUID()

    private func capture(book: UUID?, deleted: Date? = nil, id: UUID = UUID()) -> Memo {
        var meta = MemoMetadata()
        meta.bookTitle = "Some Book"
        meta.bookChapter = "4"
        meta.bookID = book
        meta.bookPosition = 100
        return Memo.make(id: id, recordedAt: Date(), transcript: "> A quote.", deletedAt: deleted, metadata: meta)
    }

    private func corpus() -> [Memo] {
        var memos: [Memo] = []
        for i in 0..<300 {
            switch i % 5 {
            case 0: memos.append(capture(book: bookA))
            case 1: memos.append(capture(book: bookB))
            case 2: memos.append(Memo.make(transcript: "plain voice memo"))
            case 3: memos.append(capture(book: bookA, deleted: Date()))   // trashed: not counted
            default: memos.append(capture(book: nil))
            }
        }
        let dup = UUID()
        memos.append(capture(book: bookB, id: dup))
        memos.append(capture(book: bookB, id: dup))                        // clone row: counts once
        return memos
    }

    // MARK: counts

    func testCountsEqualTheOldPerRowCounts() async {
        let memos = corpus()
        let expected = BookNotesJoin.counts(in: memos)
        XCTAssertEqual(expected[bookA], 60)
        XCTAssertEqual(expected[bookB], 61)

        let cache = BookNotesCountCache()
        let got = await cache.counts(for: memos, key: .init(version: 1, count: memos.count))
        XCTAssertEqual(got, expected)
        XCTAssertEqual(BookNotesJoin.counts(fromBlobs: BookNotesJoin.metadataBlobs(of: memos)), expected)
    }

    func testComputedOnceForManyRowsAndRecomputedOnANewVersion() async {
        let memos = corpus()
        let cache = BookNotesCountCache()
        let key = BookNotesCountCache.Key(version: 7, count: memos.count)
        for _ in 0..<30 {                                              // 30 "rows" asking
            let c = await cache.counts(for: memos, key: key)
            XCTAssertEqual(c[bookA], 60)
        }
        XCTAssertEqual(cache.computeCount, 1, "one pass for N rows, not one per row")

        let more = memos + [capture(book: bookA)]
        let c2 = await cache.counts(for: more, key: .init(version: 8, count: more.count))
        XCTAssertEqual(c2[bookA], 61)
        XCTAssertEqual(cache.computeCount, 2, "a new memo-set version recomputes")
    }

    func testBlobWithoutBookIDIsSkippedAndGarbageIsTolerated() {
        let id = UUID()
        let good = Data(#"{"bookID":"\#(id.uuidString)","bookTitle":"x"}"#.utf8)
        let noKey = Data(#"{"bookTitle":"x"}"#.utf8)
        let junk = Data("not json bookID".utf8)
        XCTAssertEqual(BookNotesJoin.counts(fromBlobs: [good, good, noKey, junk]), [id: 2])
    }

    // MARK: sidecar decode off the main actor

    private func makeBookFolder() throws -> (dir: URL, id: UUID, audio: URL) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("q317-\(UUID().uuidString)")
        let id = UUID()
        let folder = dir.appendingPathComponent(id.uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let audio = folder.appendingPathComponent("part1.m4a")
        FileManager.default.createFile(atPath: audio.path, contents: Data("AUDIO-BYTES".utf8))
        let store = BookTranscriptStore(directory: dir)
        var words: [WordTiming] = []
        for i in 0..<400 {
            words.append(WordTiming(word: i % 8 == 7 ? "end." : "word\(i)", start: Double(i), end: Double(i) + 0.9))
        }
        let ft = FileTranscript(fileIndex: 0, signature: store.signature(forFileAt: audio),
                                coveredUpTo: 400, words: words)
        try store.save(ft, bookID: id)
        return (dir, id, audio)
    }

    func testReadAlongSidecarDecodeRunsOffTheMainThread() async throws {
        let (dir, id, audio) = try makeBookFolder()
        defer { try? FileManager.default.removeItem(at: dir) }
        let before = BookSidecarLoader.probe.decodeCount
        XCTAssertTrue(Thread.isMainThread)
        let result = await BookSidecarLoader.readAlong(
            directory: dir, bookID: id, fileIndex: 0, audioURL: audio, fileLocal: 10)
        XCTAssertEqual(BookSidecarLoader.probe.decodeCount, before + 1)
        XCTAssertEqual(BookSidecarLoader.probe.lastRanOnMainThread, false, "the decode ran off the main thread")
        XCTAssertNotNil(result)
        XCTAssertFalse(result?.sentences.isEmpty ?? true)
        XCTAssertEqual(result?.coveredUpTo, 400)

        // Not covered past the frontier -> nil (the nudge state), same as before.
        let beyond = await BookSidecarLoader.readAlong(
            directory: dir, bookID: id, fileIndex: 0, audioURL: audio, fileLocal: 900)
        XCTAssertNil(beyond)
    }

    func testReadAlongModelPublishesAfterAnOffMainLoad() async throws {
        let (dir, id, audio) = try makeBookFolder()
        defer { try? FileManager.default.removeItem(at: dir) }
        let model = ReadAlongModel(directory: dir)
        let book = Audiobook(id: id, audioFilename: "part1.m4a", title: "T", author: "A", duration: 400)
        model.reloadIfNeeded(book: book, fileIndex: 0, fileLocal: 100, audioURL: audio)
        XCTAssertFalse(model.covered, "nothing is decoded synchronously on the caller")
        XCTAssertTrue(model.isLoading)
        for _ in 0..<200 where !model.covered { try await Task.sleep(nanoseconds: 20_000_000) }
        XCTAssertTrue(model.covered)
        XCTAssertFalse(model.isLoading)
        XCTAssertFalse(model.sentences.isEmpty)
        XCTAssertTrue(model.sentences[model.currentIndex].end > 100,
                      "the lit line is the playhead's line the moment the load lands")
    }

    func testCaptureSentencesAndCoverageCheckDecodeOffMain() async throws {
        let (dir, id, audio) = try makeBookFolder()
        defer { try? FileManager.default.removeItem(at: dir) }
        let sentences = await BookSidecarLoader.captureSentences(
            directory: dir, bookID: id, fileIndex: 0, audioURL: audio, winStart: 50, winEnd: 100)
        XCTAssertEqual(BookSidecarLoader.probe.lastRanOnMainThread, false)
        XCTAssertFalse(sentences?.isEmpty ?? true)
        let covers = await BookSidecarLoader.sidecarCovers(
            directory: dir, bookID: id, fileIndex: 0, audioURL: audio, end: 100)
        XCTAssertTrue(covers)
        let notCovers = await BookSidecarLoader.sidecarCovers(
            directory: dir, bookID: id, fileIndex: 0, audioURL: audio, end: 5_000)
        XCTAssertFalse(notCovers)
    }

    // MARK: covers

    func testCoverIsDownsampledToATier() throws {
        let size = CGSize(width: 2400, height: 2400)
        let img = UIGraphicsImageRenderer(size: size).image { ctx in
            UIColor.systemTeal.setFill(); ctx.fill(CGRect(origin: .zero, size: size))
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("q317-cover-\(UUID().uuidString).jpg")
        try XCTUnwrap(img.jpegData(compressionQuality: 0.8)).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let thumb = try XCTUnwrap(BookCoverCache.downsampled(at: url, maxPixel: 256))
        let px = max(thumb.size.width * thumb.scale, thumb.size.height * thumb.scale)
        XCTAssertLessThanOrEqual(px, 256)
        XCTAssertGreaterThan(px, 128)
        XCTAssertEqual(BookCoverCache.tier(forPoints: 1), BookCoverCache.tiers[0])
        XCTAssertEqual(BookCoverCache.tier(forPoints: 10_000), BookCoverCache.tiers.last)
    }

    // MARK: sentence starts

    /// The pre-Q317 algorithm, verbatim, as the oracle.
    private func oldSentenceStartIndices(_ words: [WordTiming]) -> [Int] {
        guard !words.isEmpty else { return [] }
        var text = ""
        var wordCharStart: [Int] = []
        for (i, w) in words.enumerated() {
            if i > 0 { text += " " }
            wordCharStart.append((text as NSString).length)
            text += w.word
        }
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text
        var starts: Set<Int> = [0]
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            let off = NSRange(range, in: text).location
            if let idx = wordCharStart.firstIndex(where: { $0 >= off }) { starts.insert(idx) }
            return true
        }
        return starts.sorted()
    }

    func testSentenceStartsMatchTheOldAlgorithmIncludingNonASCII() {
        let raw = "Mr. Smith went to Zürich. He paid 3.14 francs! Was it “cheap”? 日本語の文です。 Nope… Fine. 😀 Done."
        let words = raw.split(separator: " ").enumerated().map {
            WordTiming(word: String($0.element), start: Double($0.offset), end: Double($0.offset) + 0.5)
        }
        XCTAssertEqual(SentenceSnap.sentenceStartIndices(words), oldSentenceStartIndices(words))
        var long: [WordTiming] = []
        for i in 0..<2_000 {
            long.append(WordTiming(word: i % 9 == 8 ? "Ünï\(i)." : "wörd\(i)", start: Double(i), end: Double(i) + 0.5))
        }
        XCTAssertEqual(SentenceSnap.sentenceStartIndices(long), oldSentenceStartIndices(long))
    }
}
