import XCTest
@testable import SkriftMobile

/// Q18 (C50/C265/C218): a locally-cached JSON file that fails to decode is
/// never adopted as empty and never written back over — it's quarantined
/// (`SafeJSONStore`) and recovery is surfaced. Phone coverage: library.json +
/// bookmarks.json. (Mac coverage — names.json/settings.json — lives in
/// `SkriftDesktopTests/CorruptStoreTests.swift`.)
final class CorruptStoreTests: XCTestCase {

    private func writeGarbage(to url: URL) {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? Data("{not valid json at all".utf8).write(to: url)
    }

    private func siblings(of url: URL) -> [String] {
        (try? FileManager.default.contentsOfDirectory(atPath: url.deletingLastPathComponent().path)) ?? []
    }

    // MARK: - corrupt-library-json (R78)

    @MainActor
    func testCorruptLibraryJSONIsQuarantinedNotAdoptedEmpty() {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("audiobooks_corrupt_\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let indexURL = dir.appendingPathComponent("library.json")
        writeGarbage(to: indexURL)
        CorruptFileRegistry.shared.reset()

        let store = AudiobookLibraryStore(directory: dir)

        XCTAssertEqual(store.books.count, 0, "no other source exists yet, so this session starts empty")
        XCTAssertFalse(FileManager.default.fileExists(atPath: indexURL.path),
                        "the corrupt file must be moved aside, not left in place")
        XCTAssertTrue(siblings(of: indexURL).contains { $0.hasPrefix("library.json.corrupt-") })
        XCTAssertTrue(CorruptFileRegistry.shared.found.contains { $0.url == indexURL })
    }

    @MainActor
    func testLibraryAddAfterCorruptionDoesNotTouchTheQuarantinedFile() {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("audiobooks_corrupt2_\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let indexURL = dir.appendingPathComponent("library.json")
        writeGarbage(to: indexURL)

        let store = AudiobookLibraryStore(directory: dir)
        store.add(Audiobook(audioFilename: "a.m4b", title: "New book", author: ""))

        // A fresh read now sees exactly the one book the (post-corruption) session
        // added — the quarantined original is untouched, separate file.
        let reloaded = AudiobookLibraryStore(directory: dir)
        XCTAssertEqual(reloaded.books.map(\.title), ["New book"])
        XCTAssertTrue(siblings(of: indexURL).contains { $0.hasPrefix("library.json.corrupt-") })
    }

    // MARK: - corrupt bookmarks.json (C218/R59)

    func testCorruptBookmarksJSONIsQuarantinedNotAdoptedEmpty() {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("bm_corrupt_\(UUID().uuidString)", isDirectory: true)
        let store = BookmarkStore(directory: dir)
        let bookID = UUID()
        let fileURL = store.fileURL(bookID: bookID)
        writeGarbage(to: fileURL)
        CorruptFileRegistry.shared.reset()

        let list = store.load(bookID: bookID)

        XCTAssertEqual(list, [])
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
        XCTAssertTrue(siblings(of: fileURL).contains { $0.hasPrefix("bookmarks.json.corrupt-") })
        XCTAssertTrue(CorruptFileRegistry.shared.found.contains { $0.url == fileURL })
    }

    func testBookmarkAddAfterCorruptionDoesNotTouchTheQuarantinedFile() {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("bm_corrupt2_\(UUID().uuidString)", isDirectory: true)
        let store = BookmarkStore(directory: dir)
        let bookID = UUID()
        let fileURL = store.fileURL(bookID: bookID)
        writeGarbage(to: fileURL)

        _ = store.load(bookID: bookID)   // triggers quarantine
        _ = store.add(AudiobookBookmark(position: 42), bookID: bookID)

        let reloaded = store.load(bookID: bookID)
        XCTAssertEqual(reloaded.map(\.position), [42])
        XCTAssertTrue(siblings(of: fileURL).contains { $0.hasPrefix("bookmarks.json.corrupt-") })
    }

    // MARK: - R42: a corrupt bookmark-sync carrier blob is never adopted

    func testCorruptBookmarkSyncBlobIsIgnoredNotAdoptedEmpty() {
        let bookID = UUID()
        let record = AudiobookBookmarksRecord(bookID: bookID, itemsBlob: Data("not json".utf8),
                                              modifiedAt: Date())
        let localItems = [AudiobookBookmark(position: 5), AudiobookBookmark(position: 15)]
        let outcome = AudiobookBookmarkSyncCore.reconcile(
            bookID: bookID, localItems: localItems, localModifiedAt: .distantPast,
            records: [record],
            insert: { _ in XCTFail("must not insert on a corrupt carrier") },
            delete: { _ in })

        XCTAssertEqual(outcome, .noop, "a carrier blob that fails to decode must be ignored, never adopted as []")
    }
}
