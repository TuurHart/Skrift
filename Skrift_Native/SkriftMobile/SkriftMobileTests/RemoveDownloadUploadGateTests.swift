import XCTest
import SwiftData
@testable import SkriftMobile

/// C268 / R81 (`remove-download-mid-upload`): a synced book's local download is only
/// freed once its upload to iCloud has completed.
@MainActor
final class RemoveDownloadUploadGateTests: XCTestCase {

    private var dir: URL!
    private var lib: AudiobookLibraryStore!
    private var defaults: UserDefaults!
    private var suiteName: String!
    private var transport: InMemoryAudiobookTransport!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("rdgate_\(UUID().uuidString)")
        lib = AudiobookLibraryStore(directory: dir)
        suiteName = "rdgate_\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        transport = InMemoryAudiobookTransport()
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
        defaults.removePersistentDomain(forName: suiteName)
    }

    private func addBook(file: String = "p.m4a") -> (Audiobook, URL) {
        let book = Audiobook(id: UUID(), audioFilename: file, title: "Sapiens", author: "Harari",
                             duration: 300, lastPlayedAt: nil, position: 0, modifiedAt: .distantPast)
        lib.add(book)
        let folder = lib.folder(for: book.id)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent(file)
        FileManager.default.createFile(atPath: url.path, contents: Data("AUDIO-BYTES".utf8))
        return (book, url)
    }

    func testRemoveDownloadMidUploadKeepsLocalFile() {
        let repo = NotesRepository(inMemory: true)
        let (book, audio) = addBook()
        AudiobookCloudSync.enableSync(book: book, repository: repo)   // synced, upload not done
        XCTAssertFalse(AudiobookCloudSync.isUploadComplete(bookID: book.id, repository: repo))
        XCTAssertFalse(AudiobookCloudSync.canRemoveDownload(bookID: book.id, repository: repo))

        AudiobookCloudSync.removeDownload(bookID: book.id, library: lib, repository: repo, defaults: defaults)

        XCTAssertTrue(FileManager.default.fileExists(atPath: audio.path), "the only copy must survive")
        XCTAssertFalse(AudiobookCloudSync.isDownloadRemoved(bookID: book.id, defaults: defaults))
    }

    func testRemoveDownloadWhileUploadInFlightKeepsLocalFile() async {
        let repo = NotesRepository(inMemory: true)
        let (book, audio) = addBook()
        AudiobookCloudSync.enableSync(book: book, repository: repo)
        await AudiobookCloudSync.reconcile(library: lib, repository: repo, defaults: defaults, transport: transport)
        // Stamp is set, but a fresh upload (e.g. re-upload) is in flight on the monitor.
        let monitor = CloudSyncMonitor.shared
        _ = monitor.beginBookTransfer(book.id, direction: .up)
        defer { monitor.cancelBookTransfer(book.id) }
        XCTAssertFalse(AudiobookCloudSync.isUploadComplete(bookID: book.id, repository: repo, monitor: monitor))

        AudiobookCloudSync.removeDownload(bookID: book.id, library: lib, repository: repo, defaults: defaults)

        XCTAssertTrue(FileManager.default.fileExists(atPath: audio.path))
    }

    func testRemoveDownloadAfterUploadFreesLocalFile() async {
        let repo = NotesRepository(inMemory: true)
        let (book, audio) = addBook()
        AudiobookCloudSync.enableSync(book: book, repository: repo)
        await AudiobookCloudSync.reconcile(library: lib, repository: repo, defaults: defaults, transport: transport)
        CloudSyncMonitor.shared.cancelBookTransfer(book.id)
        XCTAssertTrue(AudiobookCloudSync.isUploadComplete(bookID: book.id, repository: repo))
        XCTAssertTrue(AudiobookCloudSync.canRemoveDownload(bookID: book.id, repository: repo))

        AudiobookCloudSync.removeDownload(bookID: book.id, library: lib, repository: repo, defaults: defaults)

        XCTAssertFalse(FileManager.default.fileExists(atPath: audio.path), "freed once the upload is complete")
        XCTAssertTrue(AudiobookCloudSync.isDownloadRemoved(bookID: book.id, defaults: defaults))
    }

    func testUnsyncedBookIsNeverRemovable() {
        let repo = NotesRepository(inMemory: true)
        let (book, audio) = addBook()
        XCTAssertFalse(AudiobookCloudSync.canRemoveDownload(bookID: book.id, repository: repo))
        AudiobookCloudSync.removeDownload(bookID: book.id, library: lib, repository: repo, defaults: defaults)
        XCTAssertTrue(FileManager.default.fileExists(atPath: audio.path))
    }
}
