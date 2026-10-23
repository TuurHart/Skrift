import XCTest

/// C164 / Q490: a retitle never renames the exported file ("rename just has to be done in
/// Obsidian" — Tuur 2026-09-22); switching the vault folder never moves old exports, new notes go
/// to the new folder, and Settings says so.
final class RetitleNoRenameTests: XCTestCase {

    private var work: URL!

    override func setUpWithError() throws {
        work = FileManager.default.temporaryDirectory.appendingPathComponent("q490r-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: work)
    }

    private func settings(folder: String = "vault") -> AppSettings {
        var s = AppSettings.default
        s.noteFolder = work.appendingPathComponent(folder).path
        return s
    }

    private func row(title: String) -> PipelineFile {
        let pf = PipelineFile(id: UUID().uuidString, filename: "note.txt", sourceType: .note)
        pf.sanitised = "Kiln shelves go in on Thursday."
        pf.enhancedTitle = title
        return pf
    }

    func testARetitleKeepsTheExportedFileName() throws {
        let pf = row(title: "Kiln shelves")
        let first = try VaultExporter.export(pf, settings: settings())

        pf.enhancedTitle = "New kiln shelves arrive"
        let second = try VaultExporter.export(pf, settings: settings())

        XCTAssertEqual(second.outcome, .updated(relativePath: first.outcome.relativePath), "same file, not renamed")
        XCTAssertEqual(first.markdownURL.lastPathComponent, "Kiln shelves.md")
        XCTAssertTrue(try String(contentsOf: second.markdownURL, encoding: .utf8).contains("New kiln shelves arrive"),
                      "the new title is inside the file")
        let notes = try FileManager.default.subpathsOfDirectory(atPath: first.markdownURL.deletingLastPathComponent().path)
            .filter { $0.hasSuffix(".md") }
        XCTAssertEqual(notes, ["Kiln shelves.md"], "no second file under the new title")
    }

    func testSwitchingTheFolderNeverMovesOldExports() throws {
        let old = row(title: "Kiln shelves")
        let first = try VaultExporter.export(old, settings: settings(folder: "vault-a"))
        let before = try String(contentsOf: first.markdownURL, encoding: .utf8)

        let fresh = row(title: "Glaze order")
        let second = try VaultExporter.export(fresh, settings: settings(folder: "vault-b"))

        XCTAssertTrue(second.markdownURL.path.hasPrefix(work.appendingPathComponent("vault-b").path),
                      "a new note goes to the new folder")
        XCTAssertEqual(try String(contentsOf: first.markdownURL, encoding: .utf8), before,
                       "the old export stays where it was, untouched")
        XCTAssertFalse(FileManager.default.fileExists(atPath: second.markdownURL.deletingLastPathComponent()
            .appendingPathComponent(first.markdownURL.lastPathComponent).path), "nothing was moved across")
    }

    func testSettingsSaysAFolderSwitchMovesNothing() {
        let help = SettingsCopy.obsidianHelp(folderName: "Skrift", canProcess: true)
        XCTAssertTrue(help.contains(SettingsCopy.folderSwitchLine), help)
        XCTAssertTrue(SettingsCopy.folderSwitchLine.contains("never moves notes already exported"))
    }
}
