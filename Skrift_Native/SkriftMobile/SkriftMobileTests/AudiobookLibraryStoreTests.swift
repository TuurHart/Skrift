import XCTest
@testable import SkriftMobile

/// The JSON-backed audiobook library: resume-position round-trips, recently-
/// played sorting, and delete cleanup. Each test gets its own temp directory.
final class AudiobookLibraryStoreTests: XCTestCase {

    @MainActor
    private func makeStore() -> AudiobookLibraryStore {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("audiobooks_\(UUID().uuidString)", isDirectory: true)
        return AudiobookLibraryStore(directory: dir)
    }

    @MainActor
    func testResumePositionRoundTripsThroughDisk() {
        let store = makeStore()
        let book = Audiobook(
            audioFilename: "book.m4b",
            title: "The Beginning of Infinity",
            author: "David Deutsch",
            duration: 54_000,
            chapters: [AudiobookChapter(title: "Creation", start: 0, duration: 54_000)]
        )
        store.add(book)
        let playedAt = Date(timeIntervalSince1970: 1_750_000_000)
        store.updateProgress(id: book.id, position: 4356, playedAt: playedAt)
        store.updateRate(id: book.id, rate: 1.25)

        // A fresh store over the same directory must read it all back.
        let reloaded = AudiobookLibraryStore(directory: store.directory)
        let read = reloaded.book(id: book.id)
        XCTAssertEqual(read?.title, "The Beginning of Infinity")
        XCTAssertEqual(read?.author, "David Deutsch")
        XCTAssertEqual(read?.position, 4356)
        XCTAssertEqual(read?.playbackRate, 1.25)
        XCTAssertEqual(read?.duration, 54_000)
        XCTAssertEqual(read?.chapters.count, 1)
        XCTAssertEqual(
            read?.lastPlayedAt?.timeIntervalSince1970 ?? 0,
            playedAt.timeIntervalSince1970,
            accuracy: 1
        )
    }

    @MainActor
    func testRecentlyPlayedSortPutsPlayedFirstThenNewestImport() {
        let store = makeStore()
        let old = Audiobook(audioFilename: "a.m4b", title: "Old import", author: "",
                            importedAt: Date(timeIntervalSinceNow: -86_400))
        let fresh = Audiobook(audioFilename: "b.m4b", title: "Fresh import", author: "")
        let played = Audiobook(audioFilename: "c.m4b", title: "Played", author: "")
        store.add(old)
        store.add(fresh)
        store.add(played)
        store.updateProgress(id: played.id, position: 60)

        XCTAssertEqual(store.sortedByRecent.map(\.title), ["Played", "Fresh import", "Old import"])
    }

    @MainActor
    func testRemoveDeletesTheBookFolder() throws {
        let store = makeStore()
        let book = Audiobook(audioFilename: "book.m4a", title: "T", author: "A")
        let folder = store.folder(for: book.id)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        FileManager.default.createFile(
            atPath: folder.appendingPathComponent("book.m4a").path, contents: Data("AUDIO".utf8)
        )
        store.add(book)

        store.remove(book)

        XCTAssertNil(store.book(id: book.id))
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.path))
    }

    @MainActor
    func testChapterLookupByPosition() {
        let book = Audiobook(
            audioFilename: "b.m4b", title: "T", author: "A", duration: 300,
            chapters: [
                AudiobookChapter(title: "One", start: 0, duration: 100),
                AudiobookChapter(title: "Two", start: 100, duration: 100),
                AudiobookChapter(title: "Three", start: 200, duration: 100),
            ]
        )
        XCTAssertEqual(book.chapterIndex(at: 0), 0)
        XCTAssertEqual(book.chapterIndex(at: 150), 1)
        XCTAssertEqual(book.chapterIndex(at: 299), 2)
        XCTAssertEqual(book.chapterNumberString(at: 150), "2")
        XCTAssertEqual(book.chapterLine(at: 150), "Chapter 2 of 3 — Two")
        XCTAssertEqual(book.shortChapterLabel(at: 150), "ch. 2 — Two")

        let chapterless = Audiobook(audioFilename: "c.m4a", title: "T", author: "A", duration: 300)
        XCTAssertNil(chapterless.chapterIndex(at: 150))
        XCTAssertNil(chapterless.chapterNumberString(at: 150))
        XCTAssertNil(chapterless.chapterLine(at: 150))
    }

    @MainActor
    func testTimeLeftAndClockFormatting() {
        var book = Audiobook(audioFilename: "b.m4b", title: "T", author: "A", duration: 43_833)
        book.position = 0
        XCTAssertEqual(AudiobookTime.clock(book.timeLeft), "12:10:33")
        XCTAssertEqual(AudiobookTime.clock(756), "12:36")
        XCTAssertEqual(AudiobookTime.clock(33), "0:33")
        XCTAssertEqual(AudiobookTime.clock(-5), "0:00")
    }
}
