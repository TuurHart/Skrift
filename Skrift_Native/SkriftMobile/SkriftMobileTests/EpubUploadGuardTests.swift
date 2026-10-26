import XCTest
@testable import SkriftMobile

/// Q522 (D221, replaces C291/Q495): an ePub added while the book's whole-book transcription is
/// still running is accepted: stored and recorded, matched after the transcript finishes.
final class EpubUploadGuardTests: XCTestCase {

    private var book: Audiobook!
    private var textFile: URL!

    override func setUp() async throws {
        book = Audiobook(audioFilename: "guard.m4a", title: "Guard Fixture", author: "Nobody", duration: 600)
        let b = book!
        await MainActor.run { AudiobookLibraryStore.shared.add(b) }
        textFile = FileManager.default.temporaryDirectory.appendingPathComponent("guard_\(UUID().uuidString).txt")
        try "The words of the book.".write(to: textFile, atomically: true, encoding: .utf8)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: textFile)
        let id = book.id
        await MainActor.run {
            if let b = AudiobookLibraryStore.shared.book(id: id) { AudiobookLibraryStore.shared.remove(b) }
        }
    }

    /// D221: the add is accepted mid-transcription; the file is stored and recorded, but no
    /// matching ran (summary has no aligned files, no alignment sidecar) — the job's finish
    /// call (`alignIfNeeded`) matches it against the full transcript.
    func testAttachIsAcceptedAndQueuedWhileThisBookTranscribes() async throws {
        let id = book.id
        let summary = try await BookAlignmentRunner.attach(bookFileAt: textFile, bookID: id,
                                                           transcribing: { $0 == id })
        XCTAssertEqual(summary.totalFiles, 0)
        XCTAssertEqual(summary.alignedFiles, 0)
        let copied = AudiobookPaths.folder(for: id).appendingPathComponent(textFile.lastPathComponent)
        XCTAssertTrue(FileManager.default.fileExists(atPath: copied.path))
        let stored = await MainActor.run { AudiobookLibraryStore.shared.book(id: id) }
        XCTAssertEqual(stored?.attachedTextFilenames, [textFile.lastPathComponent])
        XCTAssertNil(BookAlignmentStore().fileAlignment(bookID: id, fileIndex: 0),
                     "matching must wait for the transcript, not run against a partial one")
        // The attach outcome tells the user it will match up on its own.
        XCTAssertEqual(BookTextFlow.outcomeText(summary),
                       "No transcript yet \u{2014} the text will align on its own when transcription finishes.")
        // Matching is queued behind the job: while it is still working, alignIfNeeded is a no-op.
        await BookAlignmentRunner.alignIfNeeded(bookID: id)
    }

    func testAnotherBookTranscribingDoesNotAffectThisOne() async throws {
        let id = book.id
        let other = UUID()
        _ = try await BookAlignmentRunner.attach(bookFileAt: textFile, bookID: id,
                                                 transcribing: { $0 == other })
        let stored = await MainActor.run { AudiobookLibraryStore.shared.book(id: id) }
        XCTAssertEqual(stored?.attachedTextFilenames, [textFile.lastPathComponent])
    }

    /// The default path reads the real job: idle job → the add goes through.
    func testDefaultGuardReadsTheTranscriptionJob() async throws {
        let id = book.id
        let working = await MainActor.run { BookTranscriptionJob.shared.isWorking(on: id) }
        XCTAssertFalse(working)
        let viaGuard = await MainActor.run { BookAlignmentRunner.isTranscribing(id) }
        XCTAssertEqual(viaGuard, working)
        _ = try await BookAlignmentRunner.attach(bookFileAt: textFile, bookID: id)
        let stored = await MainActor.run { AudiobookLibraryStore.shared.book(id: id) }
        XCTAssertEqual(stored?.attachedTextFilenames, [textFile.lastPathComponent])
    }
}
