import XCTest

/// C158 / Q488: a picture removed from the body leaves the vault on the next export when the
/// vault copy is ours and untouched (C54); the manifest entry stays (C14). Fixture: corpus
/// `pic-deleted-after-export`. The removal lives in the shared engine (`VaultWriter.commit`),
/// so the phone's publisher runs the same step.
final class RemovedPictureExportTests: XCTestCase {

    private struct Fixture: Decodable {
        struct Metadata: Decodable { struct Entry: Decodable { let filename: String }; let imageManifest: [Entry] }
        struct Expect: Decodable { let transcriptAfterDelete: String; let removedNumbers: [Int]; let keptNumbers: [Int] }
        let id: String
        let title: String
        let transcript: String
        let metadata: Metadata
        let expect: Expect
    }

    private var work: URL!
    private var fixtureDir: URL!
    private var fixture: Fixture!

    override func setUpWithError() throws {
        work = FileManager.default.temporaryDirectory.appendingPathComponent("q488-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        fixtureDir = CorpusSeed.fixtureRoot(file: #filePath).appendingPathComponent("notes/pic-deleted-after-export")
        fixture = try JSONDecoder().decode(Fixture.self,
                                           from: Data(contentsOf: fixtureDir.appendingPathComponent("note.json")))
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: work)
    }

    private var manifest: [String] { fixture.metadata.imageManifest.map(\.filename) }

    /// The Mac row for the fixture: a working folder with `images/` + `image_manifest.json`.
    private func row(destination: NoteDestination = .personal) throws -> PipelineFile {
        let folder = work.appendingPathComponent("note")
        let images = folder.appendingPathComponent("images")
        try FileManager.default.createDirectory(at: images, withIntermediateDirectories: true)
        for name in manifest {
            try FileManager.default.copyItem(at: fixtureDir.appendingPathComponent(name),
                                             to: images.appendingPathComponent(name))
        }
        try JSONEncoder().encode(manifest.map { ImageManifestEntry(filename: $0, offsetSeconds: 0) })
            .write(to: folder.appendingPathComponent("image_manifest.json"))
        let original = folder.appendingPathComponent("original.m4a")
        try Data([1, 2, 3]).write(to: original)
        let pf = PipelineFile(id: fixture.id, filename: "memo.m4a", path: original.path, size: 3, sourceType: .audio)
        pf.enhancedTitle = fixture.title
        pf.sanitised = fixture.transcript
        pf.destination = destination
        return pf
    }

    private func settings() -> AppSettings {
        var s = AppSettings.default
        s.noteFolder = work.appendingPathComponent("vault").path
        s.portfolioRoot = work.appendingPathComponent("portfolio").path
        return s
    }

    private func pictureURL(_ r: VaultExporter.Result, _ n: Int, profile: ExportProfile = .obsidian) -> URL {
        let stem = r.markdownURL.deletingPathExtension().lastPathComponent
        let dir = profile.assetsBesideNote
            ? r.markdownURL.deletingLastPathComponent()
            : r.markdownURL.deletingLastPathComponent().appendingPathComponent(VaultLayout.images)
        return dir.appendingPathComponent(ExportProfile.pictureName(stem: stem, number: n, source: manifest[n - 1]))
    }

    private func exists(_ url: URL) -> Bool { FileManager.default.fileExists(atPath: url.path) }

    // MARK: - the shared rule

    func testRemovedPicturesAreTheManifestEntriesTheBodyNoLongerShows() {
        let removed = ExportProfile.obsidian.removedPictures(fixture.expect.transcriptAfterDelete,
                                                             manifest: manifest, stem: "Kiln")
        XCTAssertEqual(removed, [PlacedPicture(source: "photo_002.jpg", embedName: "Kiln_002.jpg")])
        XCTAssertTrue(ExportProfile.obsidian.removedPictures(fixture.transcript, manifest: manifest, stem: "Kiln").isEmpty)
    }

    // MARK: - the Mac exporter

    func testARemovedPictureLeavesTheVaultAndTheManifestStays() throws {
        let pf = try row()
        let first = try VaultExporter.export(pf, settings: settings())
        for n in [1, 2] { XCTAssertTrue(exists(pictureURL(first, n)), "picture \(n) exported") }

        pf.sanitised = fixture.expect.transcriptAfterDelete
        let second = try VaultExporter.export(pf, settings: settings())

        for n in fixture.expect.removedNumbers { XCTAssertFalse(exists(pictureURL(second, n)), "picture \(n) left the vault") }
        for n in fixture.expect.keptNumbers { XCTAssertTrue(exists(pictureURL(second, n)), "picture \(n) stays") }
        XCTAssertEqual(second.removedPictures, [pictureURL(second, 2).lastPathComponent])
        let entries = try JSONDecoder().decode([ImageManifestEntry].self, from: Data(
            contentsOf: try XCTUnwrap(pf.workingFolder).appendingPathComponent("image_manifest.json")))
        XCTAssertEqual(entries.map(\.filename), manifest, "the manifest keeps every entry (C14)")
        XCTAssertTrue(exists(try XCTUnwrap(pf.workingFolder).appendingPathComponent("images/photo_002.jpg")),
                      "the note's own copy stays")

        let third = try VaultExporter.export(pf, settings: settings())
        XCTAssertEqual(third.outcome, .unchanged(relativePath: second.outcome.relativePath))
        XCTAssertTrue(third.removedPictures.isEmpty)
    }

    func testAPictureEditedInTheVaultIsNeverRemoved() throws {
        let pf = try row()
        let first = try VaultExporter.export(pf, settings: settings())
        try Data("he drew on it".utf8).write(to: pictureURL(first, 2))

        pf.sanitised = fixture.expect.transcriptAfterDelete
        let second = try VaultExporter.export(pf, settings: settings())

        XCTAssertTrue(exists(pictureURL(second, 2)), "not ours untouched any more: it stays")
        XCTAssertTrue(second.removedPictures.isEmpty)
    }

    func testAForeignFileAtTheNameIsNeverRemoved() throws {
        // Someone else's file owns the plain name, so our copy went to the id8 name (C58).
        let pf = try row()
        let probe = try VaultExporter.export(pf, settings: settings())
        let foreign = pictureURL(probe, 2)
        try FileManager.default.removeItem(at: probe.markdownURL.deletingLastPathComponent())   // fresh vault
        try FileManager.default.createDirectory(at: foreign.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("not Skrift's".utf8).write(to: foreign)
        let first = try VaultExporter.export(pf, settings: settings())
        let ours = try FileManager.default.contentsOfDirectory(atPath: foreign.deletingLastPathComponent().path)
            .filter { $0.hasSuffix("_002 \(fixture.id.prefix(8)).jpg") }
        XCTAssertEqual(ours.count, 1, "our copy sits under the id8 name")
        _ = first

        pf.sanitised = fixture.expect.transcriptAfterDelete
        let second = try VaultExporter.export(pf, settings: settings())

        XCTAssertEqual(try Data(contentsOf: foreign), Data("not Skrift's".utf8), "the foreign file is untouched")
        XCTAssertEqual(second.removedPictures, ours, "our id8 copy goes")
        XCTAssertFalse(exists(foreign.deletingLastPathComponent().appendingPathComponent(ours[0])))
    }

    func testAPortfolioNoteRemovesThePictureBesideIt() throws {
        let pf = try row(destination: .portfolio)
        let first = try VaultExporter.export(pf, settings: settings())
        XCTAssertTrue(exists(pictureURL(first, 2, profile: .portfolio)))

        pf.sanitised = fixture.expect.transcriptAfterDelete
        let second = try VaultExporter.export(pf, settings: settings())

        XCTAssertFalse(exists(pictureURL(second, 2, profile: .portfolio)))
        XCTAssertTrue(exists(pictureURL(second, 1, profile: .portfolio)))
    }

    func testANoteEditedInTheVaultRemovesNothing() throws {
        // The note itself backed off (C54): no write, so no picture is touched either.
        let pf = try row()
        let first = try VaultExporter.export(pf, settings: settings())
        try (try String(contentsOf: first.markdownURL, encoding: .utf8) + "\nHis own line.\n")
            .write(to: first.markdownURL, atomically: true, encoding: .utf8)

        pf.sanitised = fixture.expect.transcriptAfterDelete
        let second = try VaultExporter.export(pf, settings: settings())

        XCTAssertEqual(second.outcome, .backedOffUserEdited(relativePath: first.outcome.relativePath))
        XCTAssertTrue(exists(pictureURL(first, 2)))
    }
}
