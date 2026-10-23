import XCTest
import SwiftData
@testable import SkriftMobile

/// Q499 (C298): unsharing an audiobook never leaves a phantom library entry. An entry with no
/// local file and no cloud carrier leaves the library — but only while CloudKit is healthy, only
/// on a second sighting ≥ 24 h after the first, and its folder is quarantined, never deleted.
/// Two devices = two `AudiobookLibraryStore`s over one in-memory carrier repository and one
/// in-memory audio transport (the `AudiobookCloudSyncTests` model).
@MainActor
final class PhantomEntryTests: XCTestCase {

    private var dirA: URL!, dirB: URL!
    private var libA: AudiobookLibraryStore!, libB: AudiobookLibraryStore!
    private var repo: NotesRepository!
    private var transport: InMemoryAudiobookTransport!
    private var suiteName: String!
    private var defaults: UserDefaults!
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    private let day: TimeInterval = 24 * 3600

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

    /// An entry with no file and no carrier, whose folder holds work worth keeping.
    private func addOrphan(to library: AudiobookLibraryStore) -> Audiobook {
        let orphan = Audiobook(audioFilename: "gone.m4a", title: "Orphan", author: "", duration: 300)
        library.add(orphan)
        let folder = library.folder(for: orphan.id)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: folder.appendingPathComponent("transcript_0.json").path,
                                       contents: Data("HOURS OF WORK".utf8))
        return orphan
    }

    private func sweep(_ lib: AudiobookLibraryStore, healthy: Bool = true, at date: Date) -> [UUID] {
        AudiobookCloudSync.dropPhantoms(library: lib, repository: repo, healthy: healthy, defaults: defaults, now: date)
    }

    private func quarantined(_ lib: AudiobookLibraryStore) -> [URL] {
        (try? FileManager.default.contentsOfDirectory(at: AudiobookCloudSync.quarantineRoot(lib),
                                                      includingPropertiesForKeys: nil)) ?? []
    }

    /// B received the entry but never the audio (freed on B); A unshares → two healthy loads a
    /// day apart → no empty row, and B's folder is in quarantine.
    func testUnshareThenTwoLoadsADayApartShowsNoEmptyRow() async {
        let book = addBookWithAudio(to: libA)
        AudiobookCloudSync.enableSync(book: book, repository: repo)
        AudiobookCloudSync.setDownloadRemoved(book.id, true, defaults: defaults)   // B never pulls it
        await AudiobookCloudSync.reconcile(library: libA, repository: repo, defaults: defaults, transport: transport)
        await AudiobookCloudSync.reconcile(library: libB, repository: repo, defaults: defaults, transport: transport)
        XCTAssertNotNil(libB.book(id: book.id), "B shows the synced entry while the carrier exists")

        await AudiobookCloudSync.disableSync(bookID: book.id, repository: repo, defaults: defaults, transport: transport)
        let relaunched = AudiobookLibraryStore(directory: dirB)
        XCTAssertEqual(sweep(relaunched, at: t0), [], "first sighting only remembers")
        XCTAssertNotNil(relaunched.book(id: book.id))
        XCTAssertEqual(sweep(relaunched, at: t0.addingTimeInterval(day + 60)), [book.id])
        XCTAssertNil(relaunched.book(id: book.id), "phantom entry removed")
        XCTAssertNil(AudiobookLibraryStore(directory: dirB).book(id: book.id), "persisted")
        XCTAssertNotNil(libA.book(id: book.id), "the source keeps its own copy")
    }

    func testTransientCarrierLossIsNeverDropped() {
        let orphan = addOrphan(to: libB)
        // CloudKit unhealthy (mirror reset / sign-in hiccup): nothing is even remembered.
        XCTAssertEqual(sweep(libB, healthy: false, at: t0), [])
        XCTAssertEqual(sweep(libB, healthy: false, at: t0.addingTimeInterval(3 * day)), [])
        XCTAssertNotNil(libB.book(id: orphan.id))
        // The carrier comes back between two healthy sightings → the sighting is forgotten.
        XCTAssertEqual(sweep(libB, at: t0), [])
        AudiobookCloudSync.enableSync(book: orphan, repository: repo)
        XCTAssertEqual(sweep(libB, at: t0.addingTimeInterval(2 * day)), [])
        repo.deleteAudiobookSync(bookID: orphan.id)
        XCTAssertEqual(sweep(libB, at: t0.addingTimeInterval(2 * day + 60)), [], "a fresh first sighting")
        XCTAssertNotNil(libB.book(id: orphan.id))
        XCTAssertTrue(FileManager.default.fileExists(atPath: libB.folder(for: orphan.id).path))
    }

    func testConditionSeenOnceOrWithinADayIsNotDropped() {
        let orphan = addOrphan(to: libB)
        XCTAssertEqual(sweep(libB, at: t0), [])
        XCTAssertEqual(sweep(libB, at: t0.addingTimeInterval(day - 60)), [], "second sighting under 24 h")
        XCTAssertNotNil(libB.book(id: orphan.id))
        XCTAssertEqual(sweep(libB, at: t0.addingTimeInterval(day)), [orphan.id])
    }

    func testDroppedEntrysFolderIsQuarantinedThenPrunedAfter30Days() throws {
        let orphan = addOrphan(to: libB)
        _ = sweep(libB, at: t0)
        XCTAssertEqual(sweep(libB, at: t0.addingTimeInterval(day)), [orphan.id])

        XCTAssertFalse(FileManager.default.fileExists(atPath: libB.folder(for: orphan.id).path))
        let parked = quarantined(libB)
        XCTAssertEqual(parked.count, 1)
        XCTAssertTrue(parked[0].lastPathComponent.hasPrefix(orphan.id.uuidString + "-"))
        XCTAssertEqual(try Data(contentsOf: parked[0].appendingPathComponent("transcript_0.json")),
                       Data("HOURS OF WORK".utf8), "the work survives the drop")

        AudiobookCloudSync.pruneQuarantine(library: libB, now: t0.addingTimeInterval(day + 29 * day))
        XCTAssertEqual(quarantined(libB).count, 1, "kept within 30 days")
        AudiobookCloudSync.pruneQuarantine(library: libB, now: t0.addingTimeInterval(day + 31 * day))
        XCTAssertEqual(quarantined(libB).count, 0, "pruned after 30 days")
    }

    func testAReceiverThatHasTheAudioKeepsTheBookAfterUnshare() async {
        let book = addBookWithAudio(to: libA)
        AudiobookCloudSync.enableSync(book: book, repository: repo)
        await AudiobookCloudSync.reconcile(library: libA, repository: repo, defaults: defaults, transport: transport)
        await AudiobookCloudSync.reconcile(library: libB, repository: repo, defaults: defaults, transport: transport)
        await AudiobookCloudSync.disableSync(bookID: book.id, repository: repo, defaults: defaults, transport: transport)

        _ = sweep(libB, at: t0)
        XCTAssertEqual(sweep(libB, at: t0.addingTimeInterval(2 * day)), [])
        XCTAssertNotNil(libB.book(id: book.id), "downloaded audio stays a local-only book")
    }

    func testSyncedEntriesLocalBooksAndPendingArticlesAreNeverPhantoms() {
        let waiting = Audiobook(audioFilename: "part1.m4a", title: "Waiting", author: "", duration: 300)
        libB.add(waiting)
        AudiobookCloudSync.enableSync(book: waiting, repository: repo)   // carrier exists, no file yet
        let local = addBookWithAudio(to: libB)
        var article = Audiobook(id: UUID(), files: ["article.json"], fileDurations: [0], title: "Getting the text",
                                author: "")
        article.kind = .article
        libB.add(article)

        _ = sweep(libB, at: t0)
        XCTAssertEqual(sweep(libB, at: t0.addingTimeInterval(2 * day)), [])
        XCTAssertEqual(Set(libB.books.map(\.id)), [waiting.id, local.id, article.id])
    }
}
