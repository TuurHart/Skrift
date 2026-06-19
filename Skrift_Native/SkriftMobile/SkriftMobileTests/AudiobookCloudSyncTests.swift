import XCTest
import SwiftData
@testable import SkriftMobile

/// Phase 1g/1h: per-book audiobook sync. Books are local-only until opted in; then
/// the entry + audio sync so the book appears + resumes on another device. Modelled
/// as two `AudiobookLibraryStore`s (device A / device B, separate temp folders)
/// sharing one in-memory repository (the SwiftData carrier / "state cloud") AND one
/// `InMemoryAudiobookTransport` (the raw-CloudKit "audio cloud"). Audio of a
/// non-opted book never reaches the transport.
@MainActor
final class AudiobookCloudSyncTests: XCTestCase {

    private var dirA: URL!, dirB: URL!
    private var libA: AudiobookLibraryStore!, libB: AudiobookLibraryStore!
    private var suiteName: String!
    private var defaults: UserDefaults!
    private var transport: InMemoryAudiobookTransport!

    override func setUpWithError() throws {
        dirA = FileManager.default.temporaryDirectory.appendingPathComponent("abA_\(UUID().uuidString)")
        dirB = FileManager.default.temporaryDirectory.appendingPathComponent("abB_\(UUID().uuidString)")
        libA = AudiobookLibraryStore(directory: dirA)
        libB = AudiobookLibraryStore(directory: dirB)
        suiteName = "abtest_\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        transport = InMemoryAudiobookTransport()
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dirA)
        try? FileManager.default.removeItem(at: dirB)
        defaults.removePersistentDomain(forName: suiteName)
    }

    @discardableResult
    private func addBook(to library: AudiobookLibraryStore, id: UUID = UUID(), file: String = "part1.m4a",
                         position: TimeInterval = 0, lastPlayed: Date? = nil, withFile: Bool = true,
                         modifiedAt: Date? = nil) -> Audiobook {
        let book = Audiobook(id: id, audioFilename: file, title: "Sapiens", author: "Harari",
                             duration: 300, lastPlayedAt: lastPlayed, position: position,
                             modifiedAt: modifiedAt ?? lastPlayed ?? .distantPast)
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

    func testReconcileUploadsAudioOfSyncedBookOnly() async {
        let repo = NotesRepository(inMemory: true)
        let synced = addBook(to: libA, file: "p.m4a")
        addBook(to: libA, file: "q.m4a")   // a second book, NOT opted in
        AudiobookCloudSync.enableSync(book: synced, repository: repo)

        await AudiobookCloudSync.reconcile(library: libA, repository: repo, transport: transport)

        // Exactly the opted-in book's single file reached the "audio cloud".
        XCTAssertEqual(transport.count, 1)
        XCTAssertEqual(repo.allAudiobookRecords().count, 1)
        // The source stamped audioUploadedAt (upload-once guard + receiver trigger).
        XCTAssertNotNil(repo.audiobookRecord(bookID: synced.id)?.audioUploadedAt)
    }

    /// The headline: a book opted in on A appears on B and its audio materializes.
    func testReconcileMaterializesBookOnReceiver() async {
        let repo = NotesRepository(inMemory: true)
        let book = addBook(to: libA, file: "p.m4a")
        AudiobookCloudSync.enableSync(book: book, repository: repo)
        await AudiobookCloudSync.reconcile(library: libA, repository: repo, transport: transport)   // device A: upload

        XCTAssertNil(libB.book(id: book.id))
        await AudiobookCloudSync.reconcile(library: libB, repository: repo, transport: transport)   // device B: receive

        XCTAssertNotNil(libB.book(id: book.id), "synced book appears in the receiver's library")
        let materialized = libB.folder(for: book.id).appendingPathComponent("p.m4a")
        XCTAssertEqual(try? Data(contentsOf: materialized), Data("AUDIO-BYTES".utf8), "audio materialized on B")
    }

    func testPositionSyncsLWWByModifiedAt() async {
        let repo = NotesRepository(inMemory: true)
        let id = UUID()
        // A is further along + modified recently; the record carries position 200.
        let advanced = addBook(to: libA, id: id, position: 200, lastPlayed: Date())
        AudiobookCloudSync.enableSync(book: advanced, repository: repo)
        // B has the same book but older/behind.
        addBook(to: libB, id: id, position: 50, lastPlayed: .distantPast)

        await AudiobookCloudSync.reconcile(library: libB, repository: repo, transport: transport)

        XCTAssertEqual(libB.book(id: id)?.position, 200, "B adopts A's newer resume position")
    }

    /// A speed change with NO playback (so `lastPlayedAt` is unchanged) must still sync
    /// — the reason LWW keys on `modifiedAt`, not `lastPlayedAt` (#8/#13).
    func testRateSyncsViaModifiedAt() async {
        let repo = NotesRepository(inMemory: true)
        let id = UUID()
        // A: change the speed via the store path (bumps modifiedAt, leaves lastPlayedAt nil).
        addBook(to: libA, id: id, lastPlayed: nil)
        libA.updateRate(id: id, rate: 1.5)
        AudiobookCloudSync.enableSync(book: libA.book(id: id)!, repository: repo)
        // B is behind (older modifiedAt, default rate).
        addBook(to: libB, id: id, lastPlayed: .distantPast)

        await AudiobookCloudSync.reconcile(library: libB, repository: repo, transport: transport)

        XCTAssertEqual(libB.book(id: id)?.playbackRate, 1.5, "B adopts A's newer playback rate (no playback needed)")
    }

    func testDisableDropsRecordAndCloudAudioButKeepsLocalAudio() async {
        let repo = NotesRepository(inMemory: true)
        let book = addBook(to: libA, file: "p.m4a")
        AudiobookCloudSync.enableSync(book: book, repository: repo)
        await AudiobookCloudSync.reconcile(library: libA, repository: repo, transport: transport)
        XCTAssertEqual(transport.count, 1)

        await AudiobookCloudSync.disableSync(bookID: book.id, repository: repo, defaults: defaults, transport: transport)

        XCTAssertFalse(AudiobookCloudSync.isSynced(bookID: book.id, repository: repo))
        XCTAssertEqual(transport.count, 0, "cloud audio records dropped (frees iCloud)")
        // Local audio + the library entry stay (unshare keeps local copies).
        XCTAssertTrue(FileManager.default.fileExists(atPath: libA.folder(for: book.id).appendingPathComponent("p.m4a").path))
        XCTAssertNotNil(libA.book(id: book.id))
    }

    // MARK: - Per-device Remove download (Apple Books model)

    func testRemoveDownloadFreesAudioButKeepsItSynced() async {
        let repo = NotesRepository(inMemory: true)
        let book = addBook(to: libA, file: "p.m4a")
        AudiobookCloudSync.enableSync(book: book, repository: repo)
        await AudiobookCloudSync.reconcile(library: libA, repository: repo, transport: transport)
        let audio = libA.folder(for: book.id).appendingPathComponent("p.m4a")
        XCTAssertTrue(FileManager.default.fileExists(atPath: audio.path))

        AudiobookCloudSync.removeDownload(bookID: book.id, library: libA, repository: repo, defaults: defaults)

        XCTAssertFalse(FileManager.default.fileExists(atPath: audio.path), "local audio freed")
        XCTAssertTrue(AudiobookCloudSync.isSynced(bookID: book.id, repository: repo), "still synced (record kept)")
        XCTAssertTrue(AudiobookCloudSync.isDownloadRemoved(bookID: book.id, defaults: defaults))
        // The cloud record is kept (re-downloadable) — only the local copy was freed.
        XCTAssertEqual(transport.count, 1)
    }

    func testReconcileDoesNotRedownloadARemovedBook() async {
        let repo = NotesRepository(inMemory: true)
        let book = addBook(to: libA, file: "p.m4a")
        AudiobookCloudSync.enableSync(book: book, repository: repo)
        await AudiobookCloudSync.reconcile(library: libA, repository: repo, defaults: defaults, transport: transport)
        AudiobookCloudSync.removeDownload(bookID: book.id, library: libA, repository: repo, defaults: defaults)
        let audio = libA.folder(for: book.id).appendingPathComponent("p.m4a")
        XCTAssertFalse(FileManager.default.fileExists(atPath: audio.path))

        await AudiobookCloudSync.reconcile(library: libA, repository: repo, defaults: defaults, transport: transport)

        XCTAssertFalse(FileManager.default.fileExists(atPath: audio.path),
                       "a book whose download was freed here is not auto-re-downloaded")
    }

    func testRestoreDownloadRematerializes() async {
        let repo = NotesRepository(inMemory: true)
        let book = addBook(to: libA, file: "p.m4a")
        AudiobookCloudSync.enableSync(book: book, repository: repo)
        await AudiobookCloudSync.reconcile(library: libA, repository: repo, transport: transport)   // upload the audio
        AudiobookCloudSync.removeDownload(bookID: book.id, library: libA, repository: repo, defaults: defaults)
        let audio = libA.folder(for: book.id).appendingPathComponent("p.m4a")
        XCTAssertFalse(FileManager.default.fileExists(atPath: audio.path))

        await AudiobookCloudSync.restoreDownload(bookID: book.id, library: libA, repository: repo,
                                                 defaults: defaults, transport: transport)

        XCTAssertTrue(FileManager.default.fileExists(atPath: audio.path), "re-downloaded from the kept cloud record")
        XCTAssertFalse(AudiobookCloudSync.isDownloadRemoved(bookID: book.id, defaults: defaults))
    }
}
