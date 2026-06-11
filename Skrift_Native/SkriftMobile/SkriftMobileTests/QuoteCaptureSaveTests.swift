import XCTest
@testable import SkriftMobile

/// `MemoSaver.saveQuoteCapture` — the C1 transcript shape (blockquote quote at
/// the top, ramble appended below a blank line) and the C2 book metadata
/// riding the existing metadata JSON.
final class QuoteCaptureSaveTests: XCTestCase {

    @MainActor
    private func makeSaver(repo: NotesRepository, sidecarDir: URL, transcriber: any Transcriber = SeededTranscriber(text: "unused")) -> MemoSaver {
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
        XCTAssertEqual(memo.significance, 0, "unrated → stays on the phone until the circles are set")

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

    /// C2 rides the upload `metadata` JSON to the Mac (byte-compatible:
    /// the keys appear only when present).
    @MainActor
    func testUploadMetadataCarriesBookFields() throws {
        let repo = NotesRepository(inMemory: true)
        let saver = makeSaver(repo: repo, sidecarDir: FileManager.default.temporaryDirectory)
        let id = try XCTUnwrap(saver.saveQuoteCapture(
            audioTempURL: tempAudioFile(),
            quote: "Optimism is a stance.",
            duration: 33,
            bookTitle: "The Beginning of Infinity",
            bookAuthor: "David Deutsch",
            bookChapter: "4"
        ))
        let memo = try XCTUnwrap(repo.memo(id: id))

        let data = try JSONEncoder().encode(UploadMetadata(memo: memo))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["bookTitle"] as? String, "The Beginning of Infinity")
        XCTAssertEqual(json["bookAuthor"] as? String, "David Deutsch")
        XCTAssertEqual(json["bookChapter"] as? String, "4")

        // And a plain memo emits NO book keys at all (additive contract).
        let plain = Memo(audioFilename: "memo_x.m4a", duration: 1)
        let plainJSON = try XCTUnwrap(JSONSerialization.jsonObject(
            with: try JSONEncoder().encode(UploadMetadata(memo: plain))
        ) as? [String: Any])
        XCTAssertNil(plainJSON["bookTitle"])
        XCTAssertNil(plainJSON["bookAuthor"])
        XCTAssertNil(plainJSON["bookChapter"])

        repo.permanentlyDelete(memo)
    }
}
