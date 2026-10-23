import XCTest
@testable import SkriftMobile

/// Q502 (C107, C289): every unzip checks each entry's CRC-32. A `.skriftbook` or ePub whose
/// entry bytes were flipped after zipping fails with an honest message and never unpacks
/// partially. Archives are generated here with the app's own writer, then damaged in place.
@MainActor
final class ZipCRCTests: XCTestCase {

    private func tempDir(_ name: String) -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(name)_\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        return dir
    }

    /// Flip one byte of `entry`'s stored data, found through its local file header.
    private func damage(entry name: String, in zip: URL) throws {
        var bytes = [UInt8](try Data(contentsOf: zip))
        let sig: [UInt8] = [0x50, 0x4B, 0x03, 0x04]
        var i = 0
        while i + 30 <= bytes.count {
            if Array(bytes[i..<i + 4]) == sig {
                let nameLen = Int(bytes[i + 26]) | Int(bytes[i + 27]) << 8
                let extraLen = Int(bytes[i + 28]) | Int(bytes[i + 29]) << 8
                let entryName = String(decoding: bytes[(i + 30)..<(i + 30 + nameLen)], as: UTF8.self)
                if entryName == name {
                    let dataStart = i + 30 + nameLen + extraLen
                    bytes[dataStart + 2] ^= 0xFF
                    try Data(bytes).write(to: zip)
                    return
                }
            }
            i += 1
        }
        XCTFail("no local header for \(name)")
    }

    /// A sender's book with audio + cover, packed with the app's own `BookBundle.write`.
    private func makeBundle() throws -> (book: Audiobook, bundle: URL) {
        let sender = AudiobookLibraryStore(directory: tempDir("sender"))
        let book = Audiobook(audioFilename: "book.m4a", title: "The Odyssey", author: "Homer", hasCover: true)
        let folder = sender.folder(for: book.id)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data(String(repeating: "SENDER-AUDIO ", count: 64).utf8).write(to: folder.appendingPathComponent("book.m4a"))
        try Data(String(repeating: "COVER ", count: 64).utf8).write(to: folder.appendingPathComponent("cover.jpg"))
        let bundle = tempDir("bundle").appendingPathComponent("odyssey.skriftbook")
        try BookBundle.write(book: book, folder: folder, to: bundle)
        return (book, bundle)
    }

    func testACleanBundleStillUnpacks() throws {
        let (book, bundle) = try makeBundle()
        let manifest = try BookBundle.readManifest(at: bundle)
        let receiver = AudiobookLibraryStore(directory: tempDir("receiver"))
        let folder = receiver.folder(for: book.id)
        try BookBundle.unpack(at: bundle, manifest: manifest, into: folder, library: receiver)
        XCTAssertEqual(try Data(contentsOf: folder.appendingPathComponent("book.m4a")),
                       Data(String(repeating: "SENDER-AUDIO ", count: 64).utf8))
        XCTAssertNotNil(BookBundle.coverImageData(at: bundle, manifest: manifest))
    }

    func testDamagedAudioFailsTheImportAndLeavesNothing() throws {
        let (book, bundle) = try makeBundle()
        let manifest = try BookBundle.readManifest(at: bundle)
        let audioPath = try XCTUnwrap(manifest.entryPaths.first { $0.hasPrefix("audio/") })
        try damage(entry: audioPath, in: bundle)

        let receiver = AudiobookLibraryStore(directory: tempDir("receiver"))
        let folder = receiver.folder(for: book.id)
        XCTAssertThrowsError(try BookBundle.unpack(at: bundle, manifest: manifest, into: folder, library: receiver)) { error in
            guard case BookBundle.BundleError.damaged(let name) = error else { return XCTFail("wrong error: \(error)") }
            XCTAssertEqual(name, "book.m4a")
            XCTAssertEqual((error as? LocalizedError)?.errorDescription,
                           "book.m4a is damaged inside this book file, so nothing was added. Ask for the book to be sent again.")
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.path), "never a partial unpack")
    }

    func testDamagedAudioIntoAnExistingFolderRemovesOnlyWhatThisPassWrote() throws {
        let (book, bundle) = try makeBundle()
        let manifest = try BookBundle.readManifest(at: bundle)
        try damage(entry: try XCTUnwrap(manifest.entryPaths.first { $0.hasPrefix("audio/") }), in: bundle)
        let receiver = AudiobookLibraryStore(directory: tempDir("receiver"))
        let folder = receiver.folder(for: book.id)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let keep = folder.appendingPathComponent("bookmarks.json")
        try Data("MINE".utf8).write(to: keep)

        XCTAssertThrowsError(try BookBundle.unpack(at: bundle, manifest: manifest, into: folder, library: receiver))
        XCTAssertEqual(try Data(contentsOf: keep), Data("MINE".utf8))
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.appendingPathComponent("book.m4a").path))
    }

    func testDamagedManifestIsAnHonestError() throws {
        let (_, bundle) = try makeBundle()
        try damage(entry: "manifest.json", in: bundle)
        XCTAssertThrowsError(try BookBundle.readManifest(at: bundle)) { error in
            guard case BookBundle.BundleError.damaged = error else {
                return XCTFail("a damaged manifest must say damaged, got \(error)")
            }
        }
    }

    func testDamagedCoverFallsBackToThePlaceholder() throws {
        let (_, bundle) = try makeBundle()
        let manifest = try BookBundle.readManifest(at: bundle)
        try damage(entry: "cover.jpg", in: bundle)
        XCTAssertNil(BookBundle.coverImageData(at: bundle, manifest: manifest))
    }

    /// The ePub reader goes through the same check (Q493's fixture: chapter2 flipped after zipping).
    func testDamagedEPubPartIsReportedNotRead() throws {
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<4 { root.deleteLastPathComponent() }
        let copy = tempDir("epub").appendingPathComponent("skip.epub")
        try FileManager.default.copyItem(at: root.appendingPathComponent("test-fixtures/epub/skip-report.epub"), to: copy)
        let book = try BookAlignmentRunner.parseBookFile(at: copy)
        XCTAssertTrue(book.skipped.contains(EPubSkip(part: "OEBPS/chapter2.xhtml", reason: "damaged inside the ePub file")))
        XCTAssertFalse(book.blocks.map(\.text).joined().contains("harbour froze"))
    }
}
