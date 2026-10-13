import XCTest

/// Q365 (D186, D191 — plan/perf2/g-mac-pipeline.md G8 G9 G10): an export RUN decodes the
/// export ledger once, writes it once at the end (each note's entry still lands on disk as it
/// happens, so a run that dies keeps them), and a re-export of unchanged notes reads no image
/// bytes. The vault tag scan is cached across runs and re-reads only files whose modification
/// date moved. These are work counters: never loosen them to pass.
final class MacExportWorkTests: XCTestCase {
    private var work: URL!

    override func setUpWithError() throws {
        work = FileManager.default.temporaryDirectory.appendingPathComponent("q365-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        ExportLedger.resetWork()
        VaultAttachmentOwnership.resetWork()
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: work)
    }

    // MARK: - Fixtures

    private func settings() -> AppSettings {
        var s = AppSettings.default
        s.noteFolder = work.appendingPathComponent("vault").path
        s.portfolioRoot = work.appendingPathComponent("portfolio").path
        return s
    }

    /// One processed audio note with one picture, the shape every Mac ingest writes.
    private func note(_ i: Int) throws -> PipelineFile {
        let folder = work.appendingPathComponent("notes/n\(i)")
        let images = folder.appendingPathComponent("images")
        try FileManager.default.createDirectory(at: images, withIntermediateDirectories: true)
        try Data(repeating: UInt8(i % 251), count: 4096 + i).write(to: images.appendingPathComponent("img_001.jpg"))
        let entries = [ImageManifestEntry(filename: "img_001.jpg", offsetSeconds: 0)]
        try JSONEncoder().encode(entries).write(to: folder.appendingPathComponent("image_manifest.json"))
        let audio = folder.appendingPathComponent("original.m4a")
        try Data([1, 2, 3, UInt8(i % 251)]).write(to: audio)
        let pf = PipelineFile(id: UUID().uuidString, filename: "memo\(i).m4a", path: audio.path,
                              size: 4, sourceType: .audio)
        pf.enhancedTitle = "Work note \(i)"
        pf.sanitised = "Note number \(i).\n\n[[img_001]]\n\nThe end."
        return pf
    }

    private func notes(_ n: Int) throws -> [PipelineFile] { try (0..<n).map(note) }

    @discardableResult
    private func exportRun(_ files: [PipelineFile]) throws -> [VaultExporter.Result] {
        let session = ExportSession()
        defer { session.finish() }
        return try files.map { try VaultExporter.export($0, settings: settings(), session: session) }
    }

    /// Every file under the vault, path → bytes.
    private func vaultBytes() throws -> [String: Data] {
        let root = work.appendingPathComponent("vault")
        var out: [String: Data] = [:]
        let en = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)
        while let url = en?.nextObject() as? URL {
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), !isDir.boolValue {
                out[url.path] = try Data(contentsOf: url)
            }
        }
        return out
    }

    private func home() -> URL {
        VaultExporter.exportHome(for: PipelineFile(id: "x", filename: "x.m4a", path: "", size: 0, sourceType: .audio),
                                 settings: settings())!
    }

    // MARK: - Ledger: once per run

    func testExportingFiftyNewNotesDecodesAndWritesTheLedgerOnce() throws {
        let files = try notes(50)
        let results = try exportRun(files)
        XCTAssertEqual(results.filter { if case .created = $0.outcome { return true }; return false }.count, 50)
        let w = ExportLedger.work
        XCTAssertEqual(w.decodes, 1, "one ledger decode per run, not one per note")
        XCTAssertEqual(w.writes, 1, "one full ledger write per run, at the end")

        let fresh = ExportLedger.default(for: home())
        for pf in files {
            XCTAssertNotNil(fresh.entry(for: VaultExporter.ledgerID(for: pf)), "every note's entry is on disk")
        }
    }

    func testReexportingFiftyUnchangedNotesReadsNoImageBytesAndChangesNothing() throws {
        let files = try notes(50)
        try exportRun(files)
        let before = try vaultBytes()
        ExportLedger.resetWork()
        VaultAttachmentOwnership.resetWork()

        let results = try exportRun(files)

        XCTAssertEqual(results.filter { if case .unchanged = $0.outcome { return true }; return false }.count, 50)
        XCTAssertEqual(results.map(\.imageCount), Array(repeating: 1, count: 50),
                       "the asset count the message reports stays what it was")
        let w = ExportLedger.work
        XCTAssertEqual(w.decodes, 1, "one ledger decode per run")
        XCTAssertEqual(w.writes, 1, "one ledger write per run")
        XCTAssertEqual(VaultAttachmentOwnership.work.bytesRead, 0, "an unchanged note reads no image bytes")
        XCTAssertEqual(try vaultBytes(), before, "an unchanged re-export leaves every vault byte alone")
    }

    // MARK: - Crash-safe: the entry lands as it happens

    func testEntriesLandEvenWhenTheRunNeverFinishes() throws {
        let files = try notes(3)
        let session = ExportSession()
        for pf in files { try VaultExporter.export(pf, settings: settings(), session: session) }
        // No `finish()` — the app died mid-run.
        let fresh = ExportLedger.default(for: home())
        for pf in files {
            XCTAssertNotNil(fresh.entry(for: VaultExporter.ledgerID(for: pf)), "entry survives a dead run")
        }
        session.finish()
        let compacted = ExportLedger.default(for: home())
        for pf in files { XCTAssertNotNil(compacted.entry(for: VaultExporter.ledgerID(for: pf))) }
    }

    // MARK: - The skip never hides a real change

    func testAnEditedNoteStillRewritesInsideARun() throws {
        let files = try notes(3)
        try exportRun(files)
        files[1].sanitised = "Edited words.\n\n[[img_001]]"
        let results = try exportRun(files)
        guard case .updated = results[1].outcome else { return XCTFail("edited note must rewrite: \(results[1].outcome)") }
        let md = try String(contentsOf: results[1].markdownURL, encoding: .utf8)
        XCTAssertTrue(md.contains("Edited words."))
        guard case .unchanged = results[0].outcome else { return XCTFail("untouched note stays unchanged") }
    }

    func testAReplacedVaultImageTakesTheFullPath() throws {
        let files = try notes(1)
        let first = try exportRun(files)
        let stem = first[0].markdownURL.deletingPathExtension().lastPathComponent
        let vaultImage = work.appendingPathComponent("vault").appendingPathComponent(VaultLayout.images)
            .appendingPathComponent("\(stem)_001.jpg")
        // Someone else's picture now owns the name: different bytes, different size.
        let homeImage = home().appendingPathComponent(VaultLayout.images).appendingPathComponent("\(stem)_001.jpg")
        let target = FileManager.default.fileExists(atPath: homeImage.path) ? homeImage : vaultImage
        try Data(repeating: 9, count: 10).write(to: target)

        let second = try exportRun(files)
        guard case .updated = second[0].outcome else { return XCTFail("must re-place the picture: \(second[0].outcome)") }
        let md = try String(contentsOf: second[0].markdownURL, encoding: .utf8)
        let id8 = VaultExporter.ledgerID(for: files[0]).uuidString.prefix(8)
        XCTAssertTrue(md.contains("\(stem)_001 \(id8).jpg"), "ours lands beside the foreign file: \(md)")
        XCTAssertEqual(try Data(contentsOf: target), Data(repeating: 9, count: 10), "the foreign picture is untouched")
    }

    func testAMissingVaultImageIsCopiedBack() throws {
        let files = try notes(1)
        let first = try exportRun(files)
        let stem = first[0].markdownURL.deletingPathExtension().lastPathComponent
        let image = home().appendingPathComponent(VaultLayout.images).appendingPathComponent("\(stem)_001.jpg")
        XCTAssertTrue(FileManager.default.fileExists(atPath: image.path))
        try FileManager.default.removeItem(at: image)
        try exportRun(files)
        XCTAssertTrue(FileManager.default.fileExists(atPath: image.path), "a deleted picture comes back")
    }

    // MARK: - Vault tag scan cache (G10)

    func testTagScanIsCachedAndRereadsOnlyChangedFiles() throws {
        let vault = work.appendingPathComponent("tags")
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        for i in 0..<5 {
            try "---\ntags: [t\(i)]\n---\nbody #inline\(i)".write(to: vault.appendingPathComponent("n\(i).md"),
                                                               atomically: true, encoding: .utf8)
        }
        let cache = VaultTagCache()
        let first = cache.scan(root: vault)
        XCTAssertEqual(first, VaultTagScanner.scan(root: vault), "the cache answers what a full scan answers")
        XCTAssertEqual(cache.filesRead, 5)

        XCTAssertEqual(cache.scan(root: vault), first)
        XCTAssertEqual(cache.filesRead, 5, "a second run reads nothing new")

        let changed = vault.appendingPathComponent("n2.md")
        try "---\ntags: [fresh]\n---\n".write(to: changed, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(60)],
                                              ofItemAtPath: changed.path)
        try FileManager.default.removeItem(at: vault.appendingPathComponent("n4.md"))
        let third = cache.scan(root: vault)
        XCTAssertEqual(cache.filesRead, 6, "only the changed file is re-read")
        XCTAssertEqual(third, VaultTagScanner.scan(root: vault))
        XCTAssertTrue(third.contains("fresh"))
        XCTAssertFalse(third.contains("t2"))
        XCTAssertFalse(third.contains("t4"), "a deleted note's tags leave")
    }

    func testTagScanCacheHasNoFileCap() throws {
        let vault = work.appendingPathComponent("many")
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        for i in 0..<5 {
            try "#cap\(i)".write(to: vault.appendingPathComponent("n\(i).md"), atomically: true, encoding: .utf8)
        }
        let cache = VaultTagCache(maxFiles: nil)
        XCTAssertEqual(cache.scan(root: vault).count, 5)
        XCTAssertEqual(VaultTagScanner.scan(root: vault, maxFiles: 3).count, 3, "the old cap dropped tags")
    }
}
