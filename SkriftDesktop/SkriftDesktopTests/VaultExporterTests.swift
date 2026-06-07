import XCTest

final class VaultExporterTests: XCTestCase {
    func testExportWritesMarkdownAndCopiesAudio() throws {
        let work = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: work) }

        let noteFolder = work.appendingPathComponent("note")
        try FileManager.default.createDirectory(at: noteFolder, withIntermediateDirectories: true)
        let audio = noteFolder.appendingPathComponent("original.m4a")
        try Data([1, 2, 3]).write(to: audio)
        let vault = work.appendingPathComponent("vault")

        let pf = PipelineFile(id: "1", filename: "Voice Memo.m4a", path: audio.path, size: 3, sourceType: .audio)
        pf.enhancedTitle = "My Note"
        pf.enhancedSummary = "Sum."
        pf.sanitised = "Body [[Nick Jansen]]."

        var settings = AppSettings.default
        settings.noteFolder = vault.path
        settings.audioFolder = "Voice Memos"
        settings.authorName = "Tiuri"

        let r = try VaultExporter.export(pf, settings: settings)

        XCTAssertEqual(r.markdownURL.lastPathComponent, "My Note.md")
        let md = try String(contentsOf: r.markdownURL, encoding: .utf8)
        XCTAssertTrue(md.contains("title: My Note"))
        XCTAssertTrue(md.contains("Body [[Nick Jansen]]."))

        let audioDest = vault.appendingPathComponent("Voice Memos/My Note.m4a")
        XCTAssertTrue(FileManager.default.fileExists(atPath: audioDest.path))
        XCTAssertEqual(r.audioURL?.path, audioDest.path)
    }

    func testExportThrowsWithoutVault() {
        let pf = PipelineFile(id: "1", filename: "x.m4a", path: "/tmp/x", size: 0, sourceType: .audio)
        XCTAssertThrowsError(try VaultExporter.export(pf, settings: .default))
    }
}
