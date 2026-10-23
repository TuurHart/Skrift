import XCTest

/// Q513 (C57, C58, C2): the gaps export v2 must close before the swap (Q436), with the routing
/// forced on (`ExportV2.routingOverride`): `VaultExporter.export` goes through v2 and keeps v1's
/// Q365 work counters — one ledger decode and one write per run, and a re-export of unchanged
/// notes reads no image bytes — while a real change still rewrites. And a shared document is
/// named by the one rule both apps use. The iPad half is `ExportV2DocumentPhoneTests`.
final class ExportV2SwapGapsTests: XCTestCase {
    private var work: URL!

    override func setUpWithError() throws {
        work = FileManager.default.temporaryDirectory.appendingPathComponent("q513-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        ExportLedger.resetWork()
        VaultAttachmentOwnership.resetWork()
        ExportV2.routingOverride = true
    }

    override func tearDownWithError() throws {
        ExportV2.routingOverride = nil
        try? FileManager.default.removeItem(at: work)
    }

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
        try JSONEncoder().encode([ImageManifestEntry(filename: "img_001.jpg", offsetSeconds: 0)])
            .write(to: folder.appendingPathComponent("image_manifest.json"))
        let audio = folder.appendingPathComponent("original.m4a")
        try Data([1, 2, 3, UInt8(i % 251)]).write(to: audio)
        let pf = PipelineFile(id: UUID().uuidString, filename: "memo\(i).m4a", path: audio.path,
                              size: 4, sourceType: .audio)
        pf.enhancedTitle = "Work note \(i)"
        pf.sanitised = "Note number \(i).\n\n[[img_001]]\n\nThe end."
        return pf
    }

    @discardableResult
    private func exportRun(_ files: [PipelineFile]) throws -> [VaultExporter.Result] {
        let session = ExportSession()
        defer { session.finish() }
        return try files.map { try VaultExporter.export($0, settings: settings(), session: session) }
    }

    private func vaultBytes() throws -> [String: Data] {
        var out: [String: Data] = [:]
        let en = FileManager.default.enumerator(at: work.appendingPathComponent("vault"), includingPropertiesForKeys: nil)
        while let url = en?.nextObject() as? URL {
            var dir: ObjCBool = false
            if FileManager.default.fileExists(atPath: url.path, isDirectory: &dir), !dir.boolValue {
                out[url.path] = try Data(contentsOf: url)
            }
        }
        return out
    }

    func testExportRoutesThroughV2WhenForced() throws {
        let r = try exportRun([try note(0)])
        let md = try String(contentsOf: r[0].markdownURL, encoding: .utf8)
        XCTAssertTrue(md.contains("\ncreated:"), "v2's frontmatter (D12): the routing reached v2\n\(md)")
    }

    func testFiftyNewNotesDecodeAndWriteTheLedgerOnce() throws {
        let results = try exportRun(try (0..<50).map(note))
        XCTAssertEqual(results.filter { if case .created = $0.outcome { return true }; return false }.count, 50)
        XCTAssertEqual(ExportLedger.work.decodes, 1, "one ledger decode per run")
        XCTAssertEqual(ExportLedger.work.writes, 1, "one ledger write per run")
    }

    func testReexportingFiftyUnchangedNotesReadsNoImageBytes() throws {
        let files = try (0..<50).map(note)
        try exportRun(files)
        let before = try vaultBytes()
        ExportLedger.resetWork()
        VaultAttachmentOwnership.resetWork()

        let results = try exportRun(files)

        XCTAssertEqual(results.filter { if case .unchanged = $0.outcome { return true }; return false }.count, 50)
        XCTAssertEqual(results.map(\.imageCount), Array(repeating: 1, count: 50), "the reported asset count holds")
        XCTAssertEqual(ExportLedger.work.decodes, 1)
        XCTAssertEqual(ExportLedger.work.writes, 1)
        XCTAssertEqual(VaultAttachmentOwnership.work.bytesRead, 0, "an unchanged note reads no image bytes (Q365)")
        XCTAssertEqual(try vaultBytes(), before, "and changes no vault byte")
    }

    func testTheSkipNeverHidesARealChange() throws {
        let files = try (0..<2).map(note)
        try exportRun(files)
        files[1].sanitised = "Edited words.\n\n[[img_001]]"
        let edited = try exportRun(files)
        guard case .updated = edited[1].outcome else { return XCTFail("an edit rewrites: \(edited[1].outcome)") }
        guard case .unchanged = edited[0].outcome else { return XCTFail("the other stays: \(edited[0].outcome)") }

        let stem = edited[0].markdownURL.deletingPathExtension().lastPathComponent
        let picture = edited[0].markdownURL.deletingLastPathComponent()
            .appendingPathComponent(VaultLayout.images).appendingPathComponent("\(stem)_001.jpg")
        try FileManager.default.removeItem(at: picture)
        try exportRun([files[0]])
        XCTAssertTrue(FileManager.default.fileExists(atPath: picture.path), "a deleted picture comes back")
    }

    func testOneDocumentNamingRule() {
        XCTAssertEqual(ExportV2.documentName(stem: "Marco's quote", sourceName: "Offerte kiln lijn.pdf"), "Marco's quote.pdf")
        XCTAssertEqual(ExportV2.documentName(stem: "blue-3.txt", sourceName: "blue-3.txt"), "blue-3.txt")
        XCTAssertEqual(ExportV2.documentName(stem: "Notes", sourceName: "scan"), "Notes.pdf")
    }

    func testTheSwitchIsOn() {
        XCTAssertTrue(ExportV2.isLive, "Q436")
    }
}
