import XCTest
import SwiftData
@testable import SkriftMobile

/// Q499 (C298): unsharing an audiobook never leaves a phantom library entry. An entry with no
/// local file and no cloud carrier is removed at the next library load (`reconcile`), with a
/// log line. Two devices = two `AudiobookLibraryStore`s over one in-memory carrier repository
/// and one in-memory audio transport (the `AudiobookCloudSyncTests` model).
@MainActor
final class PhantomEntryTests: XCTestCase {

    private var dirA: URL!, dirB: URL!
    private var libA: AudiobookLibraryStore!, libB: AudiobookLibraryStore!
    private var repo: NotesRepository!
    private var transport: InMemoryAudiobookTransport!
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUpWithError() throws {
        dirA = FileManager.default.temporaryDirectory.appendingPathComponent("phA_\(UUID().uuidString)")
        dirB = FileManager.default.temporaryDirectory.appendingPathComponent("phB_\(UUID().uuidString)")
        libA = AudiobookLibraryStore(directory: dirA)
        libB = AudiobookLibraryStore(directory: dirB)
        repo = NotesRepository(inMemory: true)
        transport = InMemoryAudiobookTransport()
        suiteName = "phantom_\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dirA)
        try? FileManager.default.removeItem(at: dirB)
        defaults.removePersistentDomain(forName: suiteName)
    }

    private func addBookWithAudio(to library: AudiobookLibraryStore) -> Audiobook {
        let book = Audiobook(audioFilename: "part1.m4a", title: "Sapiens", author: "Harari", duration: 300)
        library.add(book)
        let folder = library.folder(for: book.id)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: folder.appendingPathComponent("part1.m4a").path,
                                       contents: Data("AUDIO".utf8))
        return book
    }

    /// "Relaunch": a fresh store over the same folder, then the library load.
    private func reload(_ dir: URL) async -> AudiobookLibraryStore {
        let lib = AudiobookLibraryStore(directory: dir)
        await AudiobookCloudSync.reconcile(library: lib, repository: repo, defaults: defaults, transport: transport)
        return lib
    }

    /// B received the entry but never the audio (here: it was freed on B); A unshares → after
    /// B reloads, no empty row.
    func testUnshareThenReloadShowsNoEmptyRow() async {
        let book = addBookWithAudio(to: libA)
        AudiobookCloudSync.enableSync(book: book, repository: repo)
        AudiobookCloudSync.setDownloadRemoved(book.id, true, defaults: defaults)   // B never pulls it
        await AudiobookCloudSync.reconcile(library: libA, repository: repo, defaults: defaults, transport: transport)
        await AudiobookCloudSync.reconcile(library: libB, repository: repo, defaults: defaults, transport: transport)
        XCTAssertNotNil(libB.book(id: book.id), "B shows the synced entry while the carrier exists")
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: libB.folder(for: book.id).appendingPathComponent("part1.m4a").path))

        await AudiobookCloudSync.disableSync(bookID: book.id, repository: repo, defaults: defaults, transport: transport)
        let reloadedB = await reload(dirB)

        XCTAssertNil(reloadedB.book(id: book.id), "phantom entry removed")
        XCTAssertTrue(reloadedB.books.isEmpty)
        XCTAssertNotNil(libA.book(id: book.id), "the source keeps its own copy")
    }

    func testAReceiverThatHasTheAudioKeepsTheBookAfterUnshare() async {
        let book = addBookWithAudio(to: libA)
        AudiobookCloudSync.enableSync(book: book, repository: repo)
        await AudiobookCloudSync.reconcile(library: libA, repository: repo, defaults: defaults, transport: transport)
        await AudiobookCloudSync.reconcile(library: libB, repository: repo, defaults: defaults, transport: transport)
        await AudiobookCloudSync.disableSync(bookID: book.id, repository: repo, defaults: defaults, transport: transport)

        let reloadedB = await reload(dirB)
        XCTAssertNotNil(reloadedB.book(id: book.id), "downloaded audio stays a local-only book")
    }

    func testASyncedEntryStillWaitingForItsAudioIsKept() {
        let book = Audiobook(audioFilename: "part1.m4a", title: "Waiting", author: "", duration: 300)
        libB.add(book)
        AudiobookCloudSync.enableSync(book: book, repository: repo)   // carrier exists, no file yet
        XCTAssertEqual(AudiobookCloudSync.dropPhantoms(library: libB, repository: repo), [])
        XCTAssertNotNil(libB.book(id: book.id))
    }

    func testOnlyTheOrphanIsDropped() {
        let local = addBookWithAudio(to: libB)
        let orphan = Audiobook(audioFilename: "gone.m4a", title: "Orphan", author: "", duration: 300)
        libB.add(orphan)
        var article = Audiobook(id: UUID(), files: ["article.json"], fileDurations: [0], title: "Getting the text",
                                author: "")
        article.kind = .article
        libB.add(article)

        XCTAssertEqual(AudiobookCloudSync.dropPhantoms(library: libB, repository: repo), [orphan.id])
        XCTAssertEqual(Set(libB.books.map(\.id)), [local.id, article.id], "a pending article refetches; never a phantom")
        // Persisted: a relaunch reads the cleaned index.
        XCTAssertNil(AudiobookLibraryStore(directory: dirB).book(id: orphan.id))
    }
}
