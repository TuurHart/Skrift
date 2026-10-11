import XCTest
@testable import SkriftMobile

/// Q347: the quote capture used to write "> > text". `QuoteCaptureProcessor` blockquotes the
/// selection (`QuoteCaptureOutput.quote`) and `MemoSaver.saveQuoteCapture` blockquoted that
/// again, so the detail screen showed a literal "> " inside the italic quote (device feedback
/// 2b8bc952). The source is now idempotent, and an already-doubled body displays and exports
/// with one marker.
final class QuoteMarkerSourceTests: XCTestCase {

    private let sentence = "The first complete Odyssey in English was that of George Chapman, in 1615."

    // MARK: the source

    func testBlockquoteIsIdempotent() {
        let once = QuoteFormatting.blockquote(sentence)
        XCTAssertEqual(once, "> " + sentence)
        XCTAssertEqual(QuoteFormatting.blockquote(once), once, "a second pass must not add a marker")
        XCTAssertEqual(QuoteFormatting.blockquote("> > " + sentence), once, "a doubled quote heals to one")
        XCTAssertEqual(QuoteFormatting.blockquote(">> " + sentence), once)
    }

    func testBlockquoteKeepsMultilineAndBlankSpacers() {
        let twice = QuoteFormatting.blockquote(QuoteFormatting.blockquote("First.\n\nSecond."))
        XCTAssertEqual(twice, "> First.\n>\n> Second.")
    }

    @MainActor
    func testProcessorShapedQuoteSavesWithOneMarker() throws {
        let repo = NotesRepository(inMemory: true)
        let sidecarDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("wt_\(UUID().uuidString)", isDirectory: true)
        let saver = MemoSaver(repository: repo, transcriber: SeededTranscriber(text: "unused"),
                              wordTimings: WordTimingsStore(directory: sidecarDir),
                              metadataProvider: MockMetadataService())
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent("quote_\(UUID().uuidString).m4a")
        FileManager.default.createFile(atPath: temp.path, contents: Data("QUOTE-AUDIO".utf8))

        // MergedCaptureView hands the saver `output.quote`, which is already blockquoted.
        let id = try XCTUnwrap(saver.saveQuoteCapture(
            audioTempURL: temp, quote: QuoteFormatting.blockquote(sentence), duration: 11,
            bookTitle: "The Odyssey", bookAuthor: "Homer", bookChapter: "2"))
        let memo = try XCTUnwrap(repo.memo(id: id))
        XCTAssertEqual(memo.transcript, "> " + sentence)
        XCTAssertEqual(memo.captureQuote?.displayText, sentence)
        repo.permanentlyDelete(memo)
    }

    // MARK: an already-doubled body (captures saved before the fix)

    func testDoubledBodyDisplaysOneMarker() throws {
        let body = "> > \(sentence)\n\nMore blah"
        let split = try XCTUnwrap(CaptureQuote.split(body))
        XCTAssertEqual(split.displayText, sentence)
        XCTAssertEqual(split.ramble, "More blah")
        XCTAssertEqual(split.rawBlock, "> > \(sentence)\n", "the stored bytes stay verbatim")
        XCTAssertEqual(CaptureQuote.markerLength(ofLine: "> > x"), 4)
        XCTAssertEqual(CaptureQuote.markerLength(ofLine: ">> x"), 3)
        XCTAssertEqual(CaptureQuote.markerLength(ofLine: "> x"), 2)
        XCTAssertEqual(NoteCardBuilder.quoteLine(in: body), sentence)
    }

    func testDoubledBodyExportsOneMarker() {
        let out = Compiler.audiobookBody("> > \(sentence)\n\nMore blah", book: "The Odyssey", author: "Homer", chapter: "2")
        XCTAssertTrue(out.hasPrefix("> *\(sentence)*\n"), out)
        XCTAssertFalse(out.contains("> > "), out)
    }

    func testEditingADoubledQuoteWritesASingleMarker() throws {
        let split = try XCTUnwrap(CaptureQuote.split("> > \(sentence)\n\nMore blah"))
        XCTAssertEqual(split.body(withQuote: sentence + " Edited."), "> \(sentence) Edited.\n\nMore blah")
    }
}
