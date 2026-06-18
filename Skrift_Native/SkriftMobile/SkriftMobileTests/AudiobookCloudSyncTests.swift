import XCTest
import SwiftData
@testable import SkriftMobile

/// Phase 1g/1h: per-book audiobook sync. Books are local-only until opted in; then
/// the entry + audio sync so the book appears + resumes on another device. Modelled
/// as two `AudiobookLibraryStore`s (device A / device B, separate temp folders)
/// sharing one in-memory repository (the stand-in for CloudKit). Audio of a
/// non-opted book never becomes an asset.
@MainActor
final class AudiobookCloudSyncTests: XCTestCase {

    private var dirA: URL!, dirB: URL!
    private var libA: AudiobookLibraryStore!, libB: AudiobookLibraryStore!
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUpWithError() throws {
        dirA = FileManager.default.temporaryDirectory.appendingPathComponent("abA_\(UUID().uuidString)")
        dirB = FileManager.default.temporaryDirectory.appendingPathComponent("abB_\(UUID().uuidString)")
        libA = AudiobookLibraryStore(directory: dirA)
        libB = AudiobookLibraryStore(directory: dirB)
        suiteName = "abtest_\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dirA)
        try? FileManager.default.removeItem(at: dirB)
        defaults.removePersistentDomain(forName: suiteName)
    }

    @discardableResult
    private func addBook(to library: AudiobookLibraryStore, id: UUID = UUID(), file: String = "part1.m4a",
                         position: TimeInterval = 0, lastPlayed: Date? = nil, withFile: Bool = true) -> Audiobook {
        let book = Audiobook(id: id, audioFilename: file, title: "Sapiens", author: "Harari",
                             duration: 300, lastPlayedAt: lastPlayed, position: position)
        library.add(book)
        if withFile {
            let folder = library.folder(for: id)
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            FileManager.default.createFile(atPath: folder.appendingPathComponent(file).path, contents: Data("AUDIO-BYTES".utf8))
        }
        return book
    }

    func testEnableCreatesRecord() {
        let repo = NotesRepository(inMemory: true)
        let book = addBook(to: libA)
        XCTAssertFalse(AudiobookCloudSync.isSynced(bookID: book.id, repository: repo))

        AudiobookCloudSync.enableSync(book: book, repository: repo)

        XCTAssertTrue(AudiobookCloudSync.isSynced(bookID: book.id, repository: repo))
        XCTAssertEqual(repo.allAudiobookRecords().count, 1)
    }

    func testReconcileCapturesAudioOfSyncedBookOnly() {
        let repo = NotesRepository(inMemory: true)
        let synced = addBook(to: libA, file: "p.m4a")
        addBook(to: libA, file: "q.m4a")   // a second book, NOT opted in
        AudiobookCloudSync.enableSync(book: synced, repository: repo)

        AudiobookCloudSync.reconcile(library: libA, repository: repo)

        XCTAssertEqual(repo.audiobookAssets(bookID: synced.id).map(\.filename), ["p.m4a"])
        XCTAssertEqual(repo.audiobookAssets(bookID: synced.id).first?.blob, Data("AUDIO-BYTES".utf8))
        // The non-opted book's audio never leaves the device.
        XCTAssertTrue(repo.allAudiobookRecords().count == 1)
    }

    /// The headline: a book opted in on A appears on B and its audio materializes.
    func testReconcileMaterializesBookOnReceiver() {
        let repo = NotesRepository(inMemory: true)
        let book = addBook(to: libA, file: "p.m4a")
        AudiobookCloudSync.enableSync(book: book, repository: repo)
        AudiobookCloudSync.reconcile(library: libA, repository: repo)   // device A: capture

        XCTAssertNil(libB.book(id: book.id))
        AudiobookCloudSync.reconcile(library: libB, repository: repo)   // device B: receive

        XCTAssertNotNil(libB.book(id: book.id), "synced book appears in the receiver's library")
        let materialized = libB.folder(for: book.id).appendingPathComponent("p.m4a")
        XCTAssertEqual(try? Data(contentsOf: materialized), Data("AUDIO-BYTES".utf8), "audio materialized on B")
    }

    func testPositionSyncsLWWByLastPlayed() {
        let repo = NotesRepository(inMemory: true)
        let id = UUID()
        // A is further along + recently played; the record carries position 200.
        let advanced = addBook(to: libA, id: id, position: 200, lastPlayed: Date())
        AudiobookCloudSync.enableSync(book: advanced, repository: repo)
        // B has the same book but older/behind.
        addBook(to: libB, id: id, position: 50, lastPlayed: .distantPast)

        AudiobookCloudSync.reconcile(library: libB, repository: repo)

        XCTAssertEqual(libB.book(id: id)?.position, 200, "B adopts A's newer resume position")
    }

    func testDisableDropsRecordAndAssetsButKeepsLocalAudio() {
        let repo = NotesRepository(inMemory: true)
        let book = addBook(to: libA, file: "p.m4a")
        AudiobookCloudSync.enableSync(book: book, repository: repo)
        AudiobookCloudSync.reconcile(library: libA, repository: repo)
        XCTAssertEqual(repo.audiobookAssets(bookID: book.id).count, 1)

        AudiobookCloudSync.disableSync(bookID: book.id, repository: repo)

        XCTAssertFalse(AudiobookCloudSync.isSynced(bookID: book.id, repository: repo))
        XCTAssertTrue(repo.audiobookAssets(bookID: book.id).isEmpty)
        // Local audio + the library entry stay (unshare keeps local copies).
        XCTAssertTrue(FileManager.default.fileExists(atPath: libA.folder(for: book.id).appendingPathComponent("p.m4a").path))
        XCTAssertNotNil(libA.book(id: book.id))
    }

    // MARK: - Per-device Remove download (Apple Books model)

    func testRemoveDownloadFreesAudioButKeepsItSynced() {
        let repo = NotesRepository(inMemory: true)
        let book = addBook(to: libA, file: "p.m4a")
        AudiobookCloudSync.enableSync(book: book, repository: repo)
        AudiobookCloudSync.reconcile(library: libA, repository: repo)
        let audio = libA.folder(for: book.id).appendingPathComponent("p.m4a")
        XCTAssertTrue(FileManager.default.fileExists(atPath: audio.path))

        AudiobookCloudSync.removeDownload(bookID: book.id, library: libA, repository: repo, defaults: defaults)

        XCTAssertFalse(FileManager.default.fileExists(atPath: audio.path), "local audio freed")
        XCTAssertTrue(AudiobookCloudSync.isSynced(bookID: book.id, repository: repo), "still synced (record kept)")
        XCTAssertTrue(AudiobookCloudSync.isDownloadRemoved(bookID: book.id, defaults: defaults))
        // The CKAsset is kept (re-downloadable) — only the local copy was freed.
        XCTAssertEqual(repo.audiobookAssets(bookID: book.id).count, 1)
    }

    func testReconcileDoesNotRedownloadARemovedBook() {
        let repo = NotesRepository(inMemory: true)
        let book = addBook(to: libA, file: "p.m4a")
        AudiobookCloudSync.enableSync(book: book, repository: repo)
        AudiobookCloudSync.reconcile(library: libA, repository: repo, defaults: defaults)
        AudiobookCloudSync.removeDownload(bookID: book.id, library: libA, repository: repo, defaults: defaults)
        let audio = libA.folder(for: book.id).appendingPathComponent("p.m4a")
        XCTAssertFalse(FileManager.default.fileExists(atPath: audio.path))

        AudiobookCloudSync.reconcile(library: libA, repository: repo, defaults: defaults)

        XCTAssertFalse(FileManager.default.fileExists(atPath: audio.path),
                       "a book whose download was freed here is not auto-re-downloaded")
    }

    func testRestoreDownloadRematerializes() {
        let repo = NotesRepository(inMemory: true)
        let book = addBook(to: libA, file: "p.m4a")
        AudiobookCloudSync.enableSync(book: book, repository: repo)
        AudiobookCloudSync.reconcile(library: libA, repository: repo)   // capture the asset
        AudiobookCloudSync.removeDownload(bookID: book.id, library: libA, repository: repo, defaults: defaults)
        let audio = libA.folder(for: book.id).appendingPathComponent("p.m4a")
        XCTAssertFalse(FileManager.default.fileExists(atPath: audio.path))

        AudiobookCloudSync.restoreDownload(bookID: book.id, library: libA, repository: repo, defaults: defaults)

        XCTAssertTrue(FileManager.default.fileExists(atPath: audio.path), "re-downloaded from the kept CKAsset")
        XCTAssertFalse(AudiobookCloudSync.isDownloadRemoved(bookID: book.id, defaults: defaults))
    }
}
