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

    func testExportConvertsAppleNoteAttachments() throws {
        let work = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: work) }

        let noteFolder = work.appendingPathComponent("note")
        let att = noteFolder.appendingPathComponent("Attachments")
        try FileManager.default.createDirectory(at: att, withIntermediateDirectories: true)
        let mdSrc = noteFolder.appendingPathComponent("original.md")
        try "body".write(to: mdSrc, atomically: true, encoding: .utf8)
        try Data([9, 9]).write(to: att.appendingPathComponent("My Trip - 1.png"))
        let vault = work.appendingPathComponent("vault")

        let pf = PipelineFile(id: "1", filename: "export.md", path: mdSrc.path, size: 0, sourceType: .note)
        pf.enhancedTitle = "My Trip"
        pf.transcript = "Look ![](Attachments/My Trip - 1.png) end"   // ingest-rewritten ref

        var settings = AppSettings.default
        settings.noteFolder = vault.path
        settings.attachmentsFolder = "Attachments"

        let r = try VaultExporter.export(pf, settings: settings)
        let out = try String(contentsOf: r.markdownURL, encoding: .utf8)
        XCTAssertTrue(out.contains("![[My Trip - 1.png]]"), "ref → Obsidian embed")
        XCTAssertFalse(out.contains("(Attachments/"), "markdown image ref replaced")
        XCTAssertEqual(r.imageCount, 1)
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: vault.appendingPathComponent("Attachments/My Trip - 1.png").path), "attachment copied to vault")
    }

    func testExportDefaultsFoldersWhenUnset() throws {
        // attachments + audio subfolders left EMPTY → images/audio still export to
        // sensible defaults (Attachments / Voice Memos), with title-based names (E1/E2).
        let work = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: work) }

        let noteFolder = work.appendingPathComponent("note")
        let imagesDir = noteFolder.appendingPathComponent("images")
        try FileManager.default.createDirectory(at: imagesDir, withIntermediateDirectories: true)
        let audio = noteFolder.appendingPathComponent("original.m4a")
        try Data([1, 2, 3]).write(to: audio)
        try Data([9, 9]).write(to: imagesDir.appendingPathComponent("img_001.jpg"))
        let vault = work.appendingPathComponent("vault")

        let pf = PipelineFile(id: "1", filename: "memo.m4a", path: audio.path, size: 3, sourceType: .audio)
        pf.enhancedTitle = "Trip"
        pf.sanitised = "Look: [[img_001]]"

        var settings = AppSettings.default
        settings.noteFolder = vault.path
        // audioFolder + attachmentsFolder intentionally left empty

        let r = try VaultExporter.export(pf, settings: settings)
        XCTAssertEqual(r.imageCount, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: vault.appendingPathComponent("Attachments/Trip_001.jpg").path),
            "image exports to the default Attachments folder")
        XCTAssertTrue(FileManager.default.fileExists(atPath: vault.appendingPathComponent("Voice Memos/Trip.m4a").path),
            "audio exports to the default Voice Memos folder")
        XCTAssertNotNil(r.audioURL)
    }

    func testExportSkipsAudioWhenExcluded() throws {
        let work = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: work) }
        let noteFolder = work.appendingPathComponent("note")
        try FileManager.default.createDirectory(at: noteFolder, withIntermediateDirectories: true)
        let audio = noteFolder.appendingPathComponent("original.m4a")
        try Data([1, 2, 3]).write(to: audio)
        let vault = work.appendingPathComponent("vault")

        let pf = PipelineFile(id: "1", filename: "memo.m4a", path: audio.path, size: 3, sourceType: .audio)
        pf.enhancedTitle = "Trip"
        pf.includeAudioInExport = false          // ST8 opt-out

        var settings = AppSettings.default
        settings.noteFolder = vault.path
        settings.audioFolder = "Voice Memos"

        let r = try VaultExporter.export(pf, settings: settings)
        XCTAssertNil(r.audioURL, "audio not copied when includeAudioInExport is false")
    }

    func testExportThrowsWithoutVault() {
        let pf = PipelineFile(id: "1", filename: "x.m4a", path: "/tmp/x", size: 0, sourceType: .audio)
        XCTAssertThrowsError(try VaultExporter.export(pf, settings: .default))
    }

    func testExportConvertsImageMarkersToEmbeds() throws {
        let work = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: work) }

        let noteFolder = work.appendingPathComponent("note")
        let imagesDir = noteFolder.appendingPathComponent("images")
        try FileManager.default.createDirectory(at: imagesDir, withIntermediateDirectories: true)
        let audio = noteFolder.appendingPathComponent("original.m4a")
        try Data([1, 2, 3]).write(to: audio)
        try Data([9, 9]).write(to: imagesDir.appendingPathComponent("img_001.jpg"))
        let vault = work.appendingPathComponent("vault")

        let pf = PipelineFile(id: "1", filename: "memo.m4a", path: audio.path, size: 3, sourceType: .audio)
        pf.enhancedTitle = "Trip"
        pf.sanitised = "Look: [[img_001]] nice."

        var settings = AppSettings.default
        settings.noteFolder = vault.path
        settings.attachmentsFolder = "Attachments"

        let r = try VaultExporter.export(pf, settings: settings)
        XCTAssertEqual(r.imageCount, 1)
        let md = try String(contentsOf: r.markdownURL, encoding: .utf8)
        XCTAssertTrue(md.contains("![[Trip_001.jpg]]"))
        XCTAssertFalse(md.contains("[[img_001]]"))
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: vault.appendingPathComponent("Attachments/Trip_001.jpg").path))
    }
}
