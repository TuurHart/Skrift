import XCTest
import ZIPFoundation
@testable import SkriftMobile

/// Q534: a `.skriftbook` from another person can name anything. Names in its manifest that could
/// leave the book's folder are refused before and during unpacking; nothing lands outside.
final class BookBundleSafetyTests: XCTestCase {

    private var base: URL!

    override func setUpWithError() throws {
        base = FileManager.default.temporaryDirectory.appendingPathComponent("bundlesafety-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: base) }

    private func book(files: [String]) -> Audiobook {
        Audiobook(files: files, fileDurations: files.map { _ in 60 }, title: "T", author: "A",
                  duration: Double(files.count) * 60, chapters: [], hasCover: false,
                  importedAt: Date(timeIntervalSince1970: 1_000_000), position: 0, playbackRate: 1)
    }

    /// A zip holding `manifest.json` for `manifest` plus raw entries (path -> text).
    private func makeBundle(_ manifest: BookBundleManifest, entries: [String: String] = [:]) throws -> URL {
        let url = base.appendingPathComponent("b-\(UUID().uuidString).skriftbook")
        let archive = try Archive(url: url, accessMode: .create)
        let data = try JSONEncoder().encode(manifest)
        try archive.addEntry(with: "manifest.json", type: .file, uncompressedSize: Int64(data.count)) { p, s in
            data.subdata(in: Int(p)..<Int(p) + s)
        }
        for (path, text) in entries {
            let d = Data(text.utf8)
            try archive.addEntry(with: path, type: .file, uncompressedSize: Int64(d.count)) { p, s in
                d.subdata(in: Int(p)..<Int(p) + s)
            }
        }
        return url
    }

    func testManifestWithTraversalAudioNameIsRefused() throws {
        for bad in ["../evil.m4a", "/etc/evil.m4a", "..", "a/b.m4a", "x\u{0}.m4a", ""] {
            let m = BookBundleManifest(book: book(files: [bad]), audioFilenames: [bad])
            let url = try makeBundle(m)
            XCTAssertThrowsError(try BookBundle.readManifest(at: url), "audio name \(bad.debugDescription)")
        }
    }

    func testTraversalInTextTranscriptAlignmentAndCoverNamesIsRefused() throws {
        let cases: [BookBundleManifest] = [
            BookBundleManifest(book: book(files: ["a.m4a"]), audioFilenames: ["a.m4a"], textFilenames: ["../t.epub"]),
            BookBundleManifest(book: book(files: ["a.m4a"]), audioFilenames: ["a.m4a"], transcriptFilenames: [".."]),
            BookBundleManifest(book: book(files: ["a.m4a"]), audioFilenames: ["a.m4a"], alignmentFilenames: ["/abs.json"]),
            BookBundleManifest(book: book(files: ["a.m4a"]), audioFilenames: ["a.m4a"], coverFilename: "../cover.jpg"),
            // the book record's own list disagrees with the audio list
            BookBundleManifest(book: book(files: ["../x.m4a"]), audioFilenames: ["a.m4a"]),
        ]
        for m in cases {
            XCTAssertThrowsError(try BookBundle.readManifest(at: try makeBundle(m)))
        }
    }

    func testPlainNamesStillImport() throws {
        let m = BookBundleManifest(book: book(files: ["Part 1 (intro).m4a", ".hidden.m4a"]),
                                   audioFilenames: ["Part 1 (intro).m4a", ".hidden.m4a"])
        let url = try makeBundle(m, entries: ["audio/Part 1 (intro).m4a": "one", "audio/.hidden.m4a": "two"])
        let manifest = try BookBundle.readManifest(at: url)
        let lib = AudiobookLibraryStore(directory: base.appendingPathComponent("lib"))
        let folder = lib.folder(for: manifest.book.id)
        _ = try BookBundle.unpack(at: url, manifest: manifest, into: folder, library: lib)
        XCTAssertEqual(try String(contentsOf: folder.appendingPathComponent("Part 1 (intro).m4a")), "one")
        XCTAssertEqual(try String(contentsOf: folder.appendingPathComponent(".hidden.m4a")), "two")
    }

    /// `unpack` re-checks the names it is handed: a manifest that skipped `readManifest` writes nothing.
    func testUnpackRefusesAnUnsafeManifestAndWritesNothingOutside() throws {
        let lib = AudiobookLibraryStore(directory: base.appendingPathComponent("lib"))
        let m = BookBundleManifest(book: book(files: ["../escaped.m4a"]), audioFilenames: ["../escaped.m4a"])
        let url = try makeBundle(m)
        let folder = lib.folder(for: m.book.id)
        XCTAssertThrowsError(try BookBundle.unpack(at: url, manifest: m, into: folder, library: lib))
        XCTAssertFalse(FileManager.default.fileExists(atPath: base.appendingPathComponent("lib/escaped.m4a").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: base.appendingPathComponent("escaped.m4a").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.appendingPathComponent("escaped.m4a").path))
    }

    /// A symlink already sitting in the book folder cannot carry an unpack write out of it,
    /// and refusing leaves the outside file untouched.
    func testUnpackDoesNotWriteThroughASymlinkInTheFolder() throws {
        let lib = AudiobookLibraryStore(directory: base.appendingPathComponent("lib"))
        let m = BookBundleManifest(book: book(files: ["a.m4a"]), audioFilenames: ["a.m4a"])
        let url = try makeBundle(m, entries: ["audio/a.m4a": "pwn"])
        let folder = lib.folder(for: m.book.id)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let victim = base.appendingPathComponent("victim.txt")
        try "keep".write(to: victim, atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(at: folder.appendingPathComponent("a.m4a"), withDestinationURL: victim)
        XCTAssertThrowsError(try BookBundle.unpack(at: url, manifest: m, into: folder, library: lib))
        XCTAssertEqual(try String(contentsOf: victim), "keep")
    }

    // MARK: synced file names

    func testSyncedAttachmentNamesMapInsideRecordings() {
        let dir = AppPaths.recordingsDirectory
        for bad in ["../../x", "/etc/passwd", "..", "a/../../b"] {
            let entry = NoteAttachmentEntry(kind: "file", filename: bad, name: "x", uti: "public.data", byteCount: 1)
            XCTAssertTrue(PathSafety.isContained(NoteAttachmentStore.fileURL(entry), in: dir), bad)
            XCTAssertFalse(NoteAttachmentStore.fileExists(entry))
        }
    }
}
