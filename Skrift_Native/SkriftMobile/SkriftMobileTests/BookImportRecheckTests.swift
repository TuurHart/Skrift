import XCTest
@testable import SkriftMobile

/// C270 / R83: a shared-book import re-checks the library immediately before
/// unpacking. A copy that arrived (e.g. via sync) between the offer and the tap
/// on "Add" must never be overwritten.
final class BookImportRecheckTests: XCTestCase {

    private func tempDir(_ name: String) -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(name)_\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @MainActor
    func testBookThatArrivedBetweenOfferAndUnpackIsNotOverwritten() async throws {
        // Sender: a book with one audio file, packed into a .skriftbook.
        let sender = AudiobookLibraryStore(directory: tempDir("sender"))
        let book = Audiobook(audioFilename: "book.m4a", title: "The Odyssey", author: "Homer")
        let senderFolder = sender.folder(for: book.id)
        try FileManager.default.createDirectory(at: senderFolder, withIntermediateDirectories: true)
        try Data("SENDER-AUDIO".utf8).write(to: senderFolder.appendingPathComponent("book.m4a"))
        let bundle = tempDir("bundle").appendingPathComponent("odyssey.skriftbook")
        try BookBundle.write(book: book, folder: senderFolder, to: bundle)

        // Receiver: the book is NOT in the library when the import is offered.
        let receiver = AudiobookLibraryStore(directory: tempDir("receiver"))
        let bridge = BookImportBridge.shared
        bridge.offer(bundle, library: receiver)
        let pending = try XCTUnwrap(bridge.pending)
        bridge.pending = nil
        XCTAssertFalse(pending.alreadyHave)

        // ...then the same book lands (sync) before the user taps "Add".
        let receiverFolder = receiver.folder(for: book.id)
        try FileManager.default.createDirectory(at: receiverFolder, withIntermediateDirectories: true)
        let audio = receiverFolder.appendingPathComponent("book.m4a")
        try Data("LOCAL-AUDIO".utf8).write(to: audio)
        receiver.add(book)

        do {
            try await bridge.importPending(pending, library: receiver)
            XCTFail("the unpack must refuse a book that is already in the library")
        } catch let error as BookBundle.BundleError {
            guard case .alreadyInLibrary = error else { return XCTFail("wrong error: \(error)") }
        }

        XCTAssertEqual(receiver.books.filter { $0.id == book.id }.count, 1)
        XCTAssertEqual(try Data(contentsOf: audio), Data("LOCAL-AUDIO".utf8))
    }

    @MainActor
    func testFreshBookStillImports() async throws {
        let sender = AudiobookLibraryStore(directory: tempDir("sender"))
        let book = Audiobook(audioFilename: "book.m4a", title: "T", author: "A")
        let senderFolder = sender.folder(for: book.id)
        try FileManager.default.createDirectory(at: senderFolder, withIntermediateDirectories: true)
        try Data("SENDER-AUDIO".utf8).write(to: senderFolder.appendingPathComponent("book.m4a"))
        let bundle = tempDir("bundle").appendingPathComponent("t.skriftbook")
        try BookBundle.write(book: book, folder: senderFolder, to: bundle)

        let receiver = AudiobookLibraryStore(directory: tempDir("receiver"))
        let bridge = BookImportBridge.shared
        bridge.offer(bundle, library: receiver)
        let pending = try XCTUnwrap(bridge.pending)
        bridge.pending = nil

        try await bridge.importPending(pending, library: receiver)
        XCTAssertEqual(receiver.books.map(\.id), [book.id])
        XCTAssertEqual(try Data(contentsOf: receiver.folder(for: book.id).appendingPathComponent("book.m4a")),
                       Data("SENDER-AUDIO".utf8))
    }
}
