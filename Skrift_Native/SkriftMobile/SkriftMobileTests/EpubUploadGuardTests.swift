import XCTest
@testable import SkriftMobile

/// Q495 (C291): adding an ePub to a book whose whole-book transcription is still running is
/// refused with a clear message, before anything touches the book; the same book takes it
/// once transcription is not running.
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

    func testAttachIsRefusedWhileThisBookTranscribes() async throws {
        let id = book.id
        do {
            _ = try await BookAlignmentRunner.attach(bookFileAt: textFile, bookID: id,
                                                     transcribing: { $0 == id })
            XCTFail("attach must refuse while the book transcribes")
        } catch let error as BookAlignmentRunner.AttachError {
            XCTAssertEqual(error, .stillTranscribing)
            XCTAssertEqual(error.errorDescription,
                           "This book is still transcribing. Add its text once transcription finishes.")
        }
        // Nothing reached the book: no file copied in, no text recorded.
        let copied = AudiobookPaths.folder(for: id).appendingPathComponent(textFile.lastPathComponent)
        XCTAssertFalse(FileManager.default.fileExists(atPath: copied.path))
        let stored = await MainActor.run { AudiobookLibraryStore.shared.book(id: id) }
        XCTAssertEqual(stored?.attachedTextFilenames, [])
    }

    func testAnotherBookTranscribingDoesNotBlockThisOne() async throws {
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

    func testOneSentenceForEverySurface() {
        XCTAssertEqual(BookTextDisplay.addBlockedWhileTranscribing,
                       BookAlignmentRunner.AttachError.stillTranscribing.errorDescription)
    }
}
