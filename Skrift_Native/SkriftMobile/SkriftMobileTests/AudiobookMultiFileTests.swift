import XCTest
@testable import SkriftMobile

/// Multi-file (file-per-chapter) audiobooks: the additive `files` /
/// `fileDurations` model evolution with its legacy-record migration, the
/// global-time ↔ file mapping the continuous player + capture flow ride on,
/// and the importer's pure ordering/fallback helpers.
final class AudiobookMultiFileTests: XCTestCase {

    // MARK: - Migration (legacy single-file records)

    /// A library.json entry written by the PRE-multi-file build: a single
    /// `audioFilename`, no `files` / `fileDurations` keys.
    private let legacyJSON = """
    {
        "id": "11111111-2222-3333-4444-555555555555",
        "audioFilename": "book.m4b",
        "title": "The Beginning of Infinity",
        "author": "David Deutsch",
        "duration": 54000,
        "chapters": [{"title": "Creation", "start": 0, "duration": 54000}],
        "hasCover": true,
        "importedAt": 700000000,
        "position": 4356,
        "playbackRate": 1.25
    }
    """

    func testLegacyRecordDecodesIntoOneEntryFileList() throws {
        let book = try JSONDecoder().decode(Audiobook.self, from: Data(legacyJSON.utf8))
        XCTAssertEqual(book.files, ["book.m4b"], "the old audioFilename migrates to files")
        XCTAssertEqual(book.fileDurations, [54000], "the whole duration belongs to the one file")
        XCTAssertEqual(book.audioFilename, "book.m4b")
        XCTAssertEqual(book.title, "The Beginning of Infinity")
        XCTAssertEqual(book.position, 4356)
        XCTAssertEqual(book.playbackRate, 1.25)
        XCTAssertEqual(book.chapters.count, 1)
    }

    @MainActor
    func testLegacyLibraryFileLoadsThroughTheStore() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("audiobooks_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data("[\(legacyJSON)]".utf8).write(to: dir.appendingPathComponent("library.json"))

        let store = AudiobookLibraryStore(directory: dir)
        let book = try XCTUnwrap(store.books.first)
        XCTAssertEqual(book.files, ["book.m4b"])
        XCTAssertEqual(store.audioURL(of: book).lastPathComponent, "book.m4b")
        XCTAssertEqual(store.audioURL(of: book, fileIndex: 0).lastPathComponent, "book.m4b")
    }

    func testMultiFileRecordRoundTripsThroughCodable() throws {
        let book = Audiobook(
            files: ["001_a.mp3", "002_b.mp3", "003_c.mp3"],
            fileDurations: [600, 300, 100],
            title: "Steal Like an Artist",
            author: "Austin Kleon",
            duration: 1000
        )
        let decoded = try JSONDecoder().decode(Audiobook.self, from: JSONEncoder().encode(book))
        XCTAssertEqual(decoded.files, book.files)
        XCTAssertEqual(decoded.fileDurations, book.fileDurations)
        XCTAssertEqual(decoded, book)
    }

    func testEncodedRecordKeepsLegacyKeyForOlderBuilds() throws {
        let book = Audiobook(
            files: ["001_a.mp3", "002_b.mp3"],
            fileDurations: [600, 300],
            title: "T", author: "A", duration: 900
        )
        let json = try XCTUnwrap(JSONSerialization.jsonObject(
            with: JSONEncoder().encode(book)
        ) as? [String: Any])
        XCTAssertEqual(json["audioFilename"] as? String, "001_a.mp3",
                       "older builds reading the new library.json still find a file")
    }

    // MARK: - 📖 Attach-field persistence (2026-07-22, the Odyssey chapter report)

    /// Root cause of "chapters revert after relaunch": the hand-written Codable never
    /// carried the attach fields, so every library.json persist silently dropped the
    /// attachment + its derived chapters while the sidecars stayed on disk.
    func testAttachedTextFieldsRoundTripThroughCodable() throws {
        var book = Audiobook(audioFilename: "odyssey.m4b", title: "The Odyssey",
                             author: "Homer", duration: 47154)
        book.epubFilenames = ["odyssey.epub"]
        book.epubFilename = "odyssey.epub"
        book.epubChapters = [
            AudiobookChapter(title: "Introduction", start: 30, duration: 12000),
            AudiobookChapter(title: "Book 1: The Boy and the Goddess", start: 12030, duration: 2000),
        ]
        book.detectedChapters = [AudiobookChapter(title: "Opening", start: 0, duration: 47154)]

        let decoded = try JSONDecoder().decode(Audiobook.self, from: JSONEncoder().encode(book))
        XCTAssertEqual(decoded.epubFilenames, ["odyssey.epub"])
        XCTAssertEqual(decoded.epubFilename, "odyssey.epub")
        XCTAssertEqual(decoded.epubChapters, book.epubChapters)
        XCTAssertEqual(decoded, book)
        XCTAssertEqual(decoded.effectiveChapters.map(\.title),
                       ["Introduction", "Book 1: The Boy and the Goddess"],
                       "the ePub TOC must still win after a persist→relaunch round trip")
    }

    /// The sync blob must NOT gain the fields from the persistence fix — every send
    /// path encodes `sanitizedForSync()`, which nils them all first.
    func testSanitizedForSyncBlobOmitsAttachFields() throws {
        var book = Audiobook(audioFilename: "b.m4b", title: "T", author: "A", duration: 10)
        book.epubFilenames = ["x.epub"]
        book.epubFilename = "x.epub"
        book.epubChapters = [AudiobookChapter(title: "Ch", start: 0, duration: 10)]
        book.detectedChapters = [AudiobookChapter(title: "D", start: 0, duration: 10)]
        let json = try XCTUnwrap(JSONSerialization.jsonObject(
            with: JSONEncoder().encode(book.sanitizedForSync())
        ) as? [String: Any])
        XCTAssertNil(json["epubFilenames"])
        XCTAssertNil(json["epubFilename"])
        XCTAssertNil(json["epubChapters"])
        XCTAssertNil(json["detectedChapters"])
    }

    @MainActor
    func testAttachedTextFieldsSurviveAStoreReload() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("audiobooks_\(UUID().uuidString)", isDirectory: true)
        var book = Audiobook(audioFilename: "b.m4b", title: "T", author: "A", duration: 10)
        book.epubFilenames = ["x.epub"]
        book.epubFilename = "x.epub"
        book.epubChapters = [AudiobookChapter(title: "Ch 1", start: 0, duration: 10)]
        AudiobookLibraryStore(directory: dir).add(book)

        let reloaded = try XCTUnwrap(AudiobookLibraryStore(directory: dir).book(id: book.id))
        XCTAssertEqual(reloaded.attachedTextFilenames, ["x.epub"])
        XCTAssertEqual(reloaded.epubChapters?.map(\.title), ["Ch 1"],
                       "a relaunch (fresh store on the same directory) must keep ePub chapters")
    }

    func testMismatchedDurationTableIsRepairedOnDecode() throws {
        // A files list without (or with a wrong-sized) duration table spreads
        // the total evenly instead of trapping the mapping helpers.
        let json = """
        {
            "id": "11111111-2222-3333-4444-555555555555",
            "files": ["a.mp3", "b.mp3"],
            "fileDurations": [600],
            "title": "T", "author": "A", "duration": 800,
            "chapters": [], "hasCover": false, "importedAt": 0,
            "position": 0, "playbackRate": 1.0
        }
        """
        let book = try JSONDecoder().decode(Audiobook.self, from: Data(json.utf8))
        XCTAssertEqual(book.fileDurations, [400, 400])
    }

    // MARK: - Global time ↔ file mapping

    private var threeParts: Audiobook {
        Audiobook(
            files: ["001_a.mp3", "002_b.mp3", "003_c.mp3"],
            fileDurations: [600, 300, 100],
            title: "T", author: "A", duration: 1000
        )
    }

    func testFileStartTimesAreCumulative() {
        XCTAssertEqual(threeParts.fileStartTimes, [0, 600, 900])
    }

    func testFileLocationMapsGlobalTimeIntoTheRightFile() {
        let book = threeParts
        XCTAssertEqual(book.fileIndex(at: 0), 0)
        XCTAssertEqual(book.fileIndex(at: 599.9), 0)
        XCTAssertEqual(book.fileIndex(at: 600), 1, "a boundary belongs to the NEXT file")
        XCTAssertEqual(book.fileIndex(at: 750), 1)
        XCTAssertEqual(book.fileIndex(at: 1000), 2)

        let loc = book.fileLocation(at: 750)
        XCTAssertEqual(loc.index, 1)
        XCTAssertEqual(loc.offset, 150)

        let start = book.fileLocation(at: 600)
        XCTAssertEqual(start.index, 1)
        XCTAssertEqual(start.offset, 0)
    }

    func testFileBoundsConfineACaptureToOneFile() {
        let book = threeParts
        XCTAssertEqual(book.fileBounds(at: 750), CaptureSpan.Span(start: 600, end: 900))
        XCTAssertEqual(book.fileBounds(at: 10), CaptureSpan.Span(start: 0, end: 600))
        XCTAssertEqual(book.fileBounds(at: 950), CaptureSpan.Span(start: 900, end: 1000))
    }

    func testSingleFileBookMapsToWholeBook() {
        let book = Audiobook(audioFilename: "book.m4b", title: "T", author: "A", duration: 3600)
        XCTAssertEqual(book.files, ["book.m4b"])
        XCTAssertEqual(book.fileDurations, [3600])
        XCTAssertEqual(book.fileIndex(at: 1800), 0)
        XCTAssertEqual(book.fileLocation(at: 1800).offset, 1800)
        XCTAssertEqual(book.fileBounds(at: 1800), CaptureSpan.Span(start: 0, end: 3600))
    }

    @MainActor
    func testStoreResolvesPerFileURLs() {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("audiobooks_\(UUID().uuidString)", isDirectory: true)
        let store = AudiobookLibraryStore(directory: dir)
        let book = threeParts
        XCTAssertEqual(store.audioURL(of: book, fileIndex: 1).lastPathComponent, "002_b.mp3")
        XCTAssertEqual(store.audioURL(of: book, fileIndex: 99).lastPathComponent, "001_a.mp3",
                       "out-of-range clamps to the first file")
        XCTAssertEqual(store.audioURL(of: book).lastPathComponent, "001_a.mp3")
    }

    // MARK: - Importer ordering + fallback helpers (pure)

    func testSortedByFilenameUsesFinderNumericOrder() {
        let urls = ["10.mp3", "2.mp3", "1.mp3", "Chapter 21.mp3", "Chapter 3.mp3"]
            .map { URL(fileURLWithPath: "/books/Steal Like an Artist/\($0)") }
        XCTAssertEqual(
            AudiobookImporter.sortedByFilename(urls).map(\.lastPathComponent),
            ["1.mp3", "2.mp3", "10.mp3", "Chapter 3.mp3", "Chapter 21.mp3"]
        )
    }

    func testFolderFallbackNameUsesTheContainingFolder() {
        let url = URL(fileURLWithPath: "/books/Steal Like an Artist/01.mp3")
        XCTAssertEqual(AudiobookImporter.folderFallbackName(for: url), "Steal Like an Artist")
        // A bare root falls back to the filename itself.
        let rootFile = URL(fileURLWithPath: "/01.mp3")
        XCTAssertEqual(AudiobookImporter.folderFallbackName(for: rootFile), "01.mp3")
    }

    /// The fallback feeds `AudiobookMetadataDefaults.resolve` exactly like a
    /// filename: tagless multi-file imports get the folder name as the title
    /// and still trigger the confirm sheet.
    func testTaglessMultiFilePickResolvesToFolderTitle() {
        let url = URL(fileURLWithPath: "/books/Steal_Like_an_Artist/01.mp3")
        let r = AudiobookMetadataDefaults.resolve(
            title: nil, author: nil,
            filename: AudiobookImporter.folderFallbackName(for: url)
        )
        XCTAssertEqual(r.title, "Steal Like an Artist")
        XCTAssertTrue(r.needsConfirmation)
    }
}
