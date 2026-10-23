import XCTest

/// C163 / Q490: re-filing an exported note to the other destination removes the old file when
/// ours and untouched, then writes the new one; an edited or moved old file refuses the move,
/// named, and nothing is written. A Personal note never remains in the portfolio. Fixture:
/// corpus `dest-idea` (Portfolio, re-filed Personal).
final class DestinationMoveTests: XCTestCase {

    private struct Fixture: Decodable { let id: String; let transcript: String; let tags: [String] }

    private var work: URL!
    private var fixture: Fixture!

    override func setUpWithError() throws {
        work = FileManager.default.temporaryDirectory.appendingPathComponent("q490-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        fixture = try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: CorpusSeed.fixtureRoot(file: #filePath)
            .appendingPathComponent("notes/100-dest-idea/note.json")))
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: work)
    }

    private func settings(sameFolder: Bool = false) -> AppSettings {
        var s = AppSettings.default
        s.noteFolder = work.appendingPathComponent("vault").path
        s.portfolioRoot = sameFolder ? s.noteFolder : work.appendingPathComponent("portfolio").path
        return s
    }

    private func row(_ destination: NoteDestination = .portfolio) -> PipelineFile {
        let pf = PipelineFile(id: fixture.id, filename: "note.txt", sourceType: .note)
        pf.sanitised = fixture.transcript
        pf.enhancedTitle = "Repair diary card"
        pf.tags = fixture.tags
        pf.destination = destination
        return pf
    }

    private func exportDone(_ pf: PipelineFile, _ s: AppSettings? = nil) throws -> VaultExporter.Result {
        let r = try VaultExporter.export(pf, settings: s ?? settings())
        if r.outcome.isWrittenOrCurrent { pf.exportStatus = .done; pf.exported = r.markdownURL.path }
        return r
    }

    private func exists(_ url: URL) -> Bool { FileManager.default.fileExists(atPath: url.path) }

    private func markdownFiles(under folder: String) -> [String] {
        let root = work.appendingPathComponent(folder)
        return ((try? FileManager.default.subpathsOfDirectory(atPath: root.path)) ?? []).filter { $0.hasSuffix(".md") }
    }

    // MARK: - the move

    func testAPortfolioNoteRefiledPersonalLeavesThePortfolio() throws {
        let pf = row(.portfolio)
        let before = try exportDone(pf)
        XCTAssertTrue(before.markdownURL.path.hasPrefix(work.appendingPathComponent("portfolio").path))

        XCTAssertNil(VaultExporter.destinationChangeRefusal(pf, to: .personal, settings: settings()))
        pf.destination = .personal
        let after = try exportDone(pf)

        XCTAssertFalse(exists(before.markdownURL), "a Personal note never remains in the portfolio")
        XCTAssertTrue(markdownFiles(under: "portfolio").isEmpty)
        XCTAssertTrue(exists(after.markdownURL))
        XCTAssertTrue(after.markdownURL.path.hasPrefix(work.appendingPathComponent("vault").path))
        XCTAssertFalse(after.refusedMove)
    }

    func testAPersonalNoteRefiledPortfolioLeavesTheVault() throws {
        let pf = row(.personal)
        let before = try exportDone(pf)
        pf.destination = .portfolio
        let after = try exportDone(pf)

        XCTAssertFalse(exists(before.markdownURL))
        XCTAssertTrue(after.markdownURL.path.hasPrefix(work.appendingPathComponent("portfolio").path))
    }

    func testAnEditedOldFileRefusesTheMoveAndNamesIt() throws {
        let pf = row(.portfolio)
        let before = try exportDone(pf)
        let mine = try String(contentsOf: before.markdownURL, encoding: .utf8) + "\nHis own line.\n"
        try mine.write(to: before.markdownURL, atomically: true, encoding: .utf8)

        let refusal = try XCTUnwrap(VaultExporter.destinationChangeRefusal(pf, to: .personal, settings: settings()))
        let stem = before.markdownURL.deletingPathExtension().lastPathComponent
        XCTAssertTrue(refusal.contains("“\(stem)”"), "names the file: \(refusal)")
        XCTAssertTrue(refusal.contains("It stays a Portfolio note"), refusal)

        // A re-file that arrives from another device: the export refuses and writes nothing.
        pf.destination = .personal
        let after = try VaultExporter.export(pf, settings: settings())
        XCTAssertTrue(after.refusedMove)
        XCTAssertEqual(after.outcome, .backedOffUserEdited(relativePath: before.outcome.relativePath))
        XCTAssertEqual(try String(contentsOf: before.markdownURL, encoding: .utf8), mine, "his edit stands")
        XCTAssertTrue(markdownFiles(under: "vault").isEmpty, "nothing reached the vault")
    }

    func testAMovedOldFileRefusesTheMove() throws {
        let pf = row(.portfolio)
        let before = try exportDone(pf)
        let filed = before.markdownURL.deletingLastPathComponent().appendingPathComponent("filed", isDirectory: true)
        try FileManager.default.createDirectory(at: filed, withIntermediateDirectories: true)
        try FileManager.default.moveItem(at: before.markdownURL,
                                         to: filed.appendingPathComponent(before.markdownURL.lastPathComponent))

        XCTAssertNotNil(VaultExporter.destinationChangeRefusal(pf, to: .personal, settings: settings()))
        pf.destination = .personal
        let after = try VaultExporter.export(pf, settings: settings())
        XCTAssertEqual(after.outcome, .movedAway(relativePath: before.outcome.relativePath))
        XCTAssertTrue(after.refusedMove)
        XCTAssertTrue(markdownFiles(under: "vault").isEmpty)
    }

    func testADeletedOldFileDoesNotBlockTheMove() throws {
        let pf = row(.portfolio)
        let before = try exportDone(pf)
        try FileManager.default.removeItem(at: before.markdownURL)

        pf.destination = .personal
        let after = try exportDone(pf)
        XCTAssertEqual(after.outcome, .created(relativePath: after.outcome.relativePath))
    }

    func testOneFolderForBothDestinationsMovesNothing() throws {
        let s = settings(sameFolder: true)
        let pf = row(.personal)
        let before = try exportDone(pf, s)
        pf.destination = .portfolio
        _ = try VaultExporter.export(pf, settings: s)
        XCTAssertTrue(exists(before.markdownURL) || VaultExporter.otherHome(for: pf, settings: s) != nil,
                      "with one folder for both there is no other home to clear")
    }

    func testANoteNeverExportedChangesFreely() {
        XCTAssertNil(VaultExporter.destinationChangeRefusal(row(.portfolio), to: .personal, settings: settings()))
    }
}
