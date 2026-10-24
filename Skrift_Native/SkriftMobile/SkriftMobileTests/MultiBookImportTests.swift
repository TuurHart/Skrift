import AVFoundation
import XCTest
@testable import SkriftMobile

/// Q497 (C293): picking several distinct books at once yields one library entry per book —
/// never one merged book. Fixture: tiny AAC files generated here (silence, album-tagged),
/// two parts of "Book A" and two of "Book B" in one folder, the shape a Files multi-select has.
final class MultiBookImportTests: XCTestCase {

    private var work: URL!

    override func setUp() async throws {
        work = FileManager.default.temporaryDirectory.appendingPathComponent("multibook_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: work)
    }

    // MARK: - Fixture

    /// One second of silence as AAC in an .m4a, with an album tag when given.
    private func makePart(_ name: String, album: String?, in folder: URL) async throws -> URL {
        let raw = work.appendingPathComponent("raw_\(UUID().uuidString).m4a")
        let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
        do {
            let file = try AVAudioFile(forWriting: raw, settings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 44_100, AVNumberOfChannelsKey: 1,
            ])
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 44_100)!
            buffer.frameLength = 44_100
            try file.write(from: buffer)
        }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let out = folder.appendingPathComponent(name)
        let export = try XCTUnwrap(AVAssetExportSession(asset: AVURLAsset(url: raw),
                                                        presetName: AVAssetExportPresetPassthrough))
        export.outputURL = out
        export.outputFileType = .m4a
        if let album {
            let item = AVMutableMetadataItem()
            item.identifier = .iTunesMetadataAlbum
            item.value = album as NSString
            export.metadata = [item]
        }
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            export.exportAsynchronously { c.resume() }
        }
        XCTAssertEqual(export.status, .completed, "\(String(describing: export.error))")
        return out
    }

    private func file(_ path: String, album: String? = nil, whole: Bool = false) -> AudiobookImporter.PickedFile {
        .init(url: URL(fileURLWithPath: path), album: album, wholeBook: whole)
    }

    // MARK: - Grouping (pure)

    func testDistinctAlbumsAreDistinctBooks() {
        let groups = AudiobookImporter.bookGroups([
            file("/p/01.mp3", album: "Book A"), file("/p/01b.mp3", album: "Book B"),
            file("/p/02.mp3", album: "Book A"), file("/p/02b.mp3", album: "book b "),
        ])
        XCTAssertEqual(groups.map { $0.map(\.lastPathComponent) }, [["01.mp3", "02.mp3"], ["01b.mp3", "02b.mp3"]])
    }

    func testOneBooksPartsStayOneBook() {
        let tagged = AudiobookImporter.bookGroups([file("/p/1.mp3", album: "X"), file("/p/2.mp3", album: "X")])
        XCTAssertEqual(tagged.count, 1)
        let untagged = AudiobookImporter.bookGroups([file("/p/1.mp3"), file("/p/2.mp3"), file("/p/3.mp3")])
        XCTAssertEqual(untagged.count, 1, "untagged parts in one folder are one book, as before")
    }

    func testWholeBookFilesStandAlone() {
        let groups = AudiobookImporter.bookGroups([
            file("/p/a.m4b", whole: true), file("/p/b.m4b", whole: true), file("/p/c.mp3", album: "C"),
        ])
        XCTAssertEqual(groups.count, 3)
    }

    func testAStrayUntaggedPartJoinsItsFoldersOneBook() {
        let groups = AudiobookImporter.bookGroups([
            file("/p/1.mp3", album: "Book A"), file("/p/2.mp3"), file("/p/3.mp3", album: "Book A"),
        ])
        XCTAssertEqual(groups.map(\.count), [3])
    }

    func testUntaggedPartsInDifferentFoldersAreDifferentBooks() {
        let groups = AudiobookImporter.bookGroups([file("/a/1.mp3"), file("/b/1.mp3")])
        XCTAssertEqual(groups.count, 2)
    }

    // MARK: - The real import

    func testTwoBooksPickedTogetherBecomeTwoLibraryEntries() async throws {
        let pick = work.appendingPathComponent("Downloads")
        let a1 = try await makePart("A-01.m4a", album: "Book A", in: pick)
        let b1 = try await makePart("B-01.m4a", album: "Book B", in: pick)
        let a2 = try await makePart("A-02.m4a", album: "Book A", in: pick)
        let b2 = try await makePart("B-02.m4a", album: "Book B", in: pick)

        let libraryDir = work.appendingPathComponent("library")
        let result = try await AudiobookImporter.importBooks(from: [a1, b1, a2, b2], libraryDirectory: libraryDir)
        XCTAssertTrue(result.failures.isEmpty, "\(result.failures)")
        XCTAssertEqual(result.books.count, 2)
        XCTAssertEqual(Set(result.books.map(\.book.title)), ["Book A", "Book B"])
        XCTAssertEqual(result.books.map(\.book.files.count), [2, 2])

        let store = await MainActor.run { AudiobookLibraryStore(directory: libraryDir) }
        await MainActor.run { for p in result.books { store.add(p.book) } }
        let entries = await MainActor.run { store.books.count }
        XCTAssertEqual(entries, 2)
    }

    func testOneBooksPartsStillImportAsOneBook() async throws {
        let pick = work.appendingPathComponent("Steal Like an Artist")
        let p1 = try await makePart("01.m4a", album: "Steal Like an Artist", in: pick)
        let p2 = try await makePart("02.m4a", album: "Steal Like an Artist", in: pick)
        let result = try await AudiobookImporter.importBooks(from: [p2, p1],
                                                             libraryDirectory: work.appendingPathComponent("library"))
        XCTAssertEqual(result.books.count, 1)
        XCTAssertEqual(result.books.first?.book.files, ["001_01.m4a", "002_02.m4a"])
    }
}
