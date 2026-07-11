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
        XCTAssertTrue(md.contains("title: \"My Note\""))
        XCTAssertTrue(md.contains("Body [[Nick Jansen]]."))

        let audioDest = vault.appendingPathComponent("Voice Memos/My Note.m4a")
        XCTAssertTrue(FileManager.default.fileExists(atPath: audioDest.path))
        XCTAssertEqual(r.audioURL?.path, audioDest.path)
    }

    func testExportStripsObsidianForbiddenTitleCharacters() throws {
        let work = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: work) }
        let vault = work.appendingPathComponent("vault")

        // Gemma loves "Title: Subtitle" — Obsidian forbids : (and * " \ / < > | ?,
        // plus # ^ [ ] which break wikilinks). Slashes keep a word boundary as "-";
        // the rest strip without leaving doubled spaces.
        let pf = PipelineFile(id: "1", filename: "x", path: "", size: 0, sourceType: .capture)
        pf.enhancedTitle = #"A: B / C "D" [E] #F | G?"#
        pf.transcript = "Body."

        var settings = AppSettings.default
        settings.noteFolder = vault.path

        let r = try VaultExporter.export(pf, settings: settings)
        XCTAssertEqual(r.markdownURL.lastPathComponent, "A B - C D E F G.md")
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

    func testExportConvertsCaptureImageMarkers() throws {
        // Share Wave 2: image captures inline photos as [[img_NNN]] in the annotation.
        // A capture's `path` IS the working folder (images/ inside it) — markers must
        // convert to ![[<title>_NNN.ext]] embeds exactly like memos, not export literally.
        let work = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: work) }

        let captureFolder = work.appendingPathComponent("capture_1")
        let imagesDir = captureFolder.appendingPathComponent("images")
        try FileManager.default.createDirectory(at: imagesDir, withIntermediateDirectories: true)
        try Data([9, 9]).write(to: imagesDir.appendingPathComponent("photo_AAA_001.jpg"))
        try Data([8, 8]).write(to: imagesDir.appendingPathComponent("photo_AAA_002.jpg"))
        let vault = work.appendingPathComponent("vault")

        let pf = PipelineFile(id: "1", filename: "capture_1", path: captureFolder.path, size: 0, sourceType: .capture)
        pf.enhancedTitle = "Whiteboard"
        let meta: [String: Any] = ["sharedContent": ["type": "image", "fileName": "IMG_2041.jpeg"]]
        pf.audioMetadataJSON = try JSONSerialization.data(withJSONObject: meta)
        pf.transcript = "Nick's diagram.\n\n[[img_001]]\n\n[[img_002]]"

        var settings = AppSettings.default
        settings.noteFolder = vault.path
        settings.attachmentsFolder = "Attachments"

        let r = try VaultExporter.export(pf, settings: settings)
        XCTAssertEqual(r.imageCount, 2)
        let md = try String(contentsOf: r.markdownURL, encoding: .utf8)
        XCTAssertTrue(md.contains("![[Whiteboard_001.jpg]]"))
        XCTAssertTrue(md.contains("![[Whiteboard_002.jpg]]"))
        XCTAssertFalse(md.contains("[[img_00"), "no literal markers in the vault note")
        XCTAssertFalse(md.contains("IMG_2041"), "no stale pinned first-image embed")
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: vault.appendingPathComponent("Attachments/Whiteboard_001.jpg").path))
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: vault.appendingPathComponent("Attachments/Whiteboard_002.jpg").path))
    }

    func testExportLegacyCaptureCopiesImagesUnderOriginalNames() throws {
        // Pre-Wave-2 captures: no markers in the body — the Compiler pins ![[fileName]]
        // and the exporter copies the folder's images under their original names.
        let work = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: work) }

        let captureFolder = work.appendingPathComponent("capture_1")
        let imagesDir = captureFolder.appendingPathComponent("images")
        try FileManager.default.createDirectory(at: imagesDir, withIntermediateDirectories: true)
        try Data([9, 9]).write(to: imagesDir.appendingPathComponent("whiteboard.jpg"))
        let vault = work.appendingPathComponent("vault")

        let pf = PipelineFile(id: "1", filename: "capture_1", path: captureFolder.path, size: 0, sourceType: .capture)
        pf.enhancedTitle = "Whiteboard"
        let meta: [String: Any] = ["sharedContent": ["type": "image", "fileName": "whiteboard.jpg"]]
        pf.audioMetadataJSON = try JSONSerialization.data(withJSONObject: meta)
        pf.transcript = "Nick's diagram."

        var settings = AppSettings.default
        settings.noteFolder = vault.path
        settings.attachmentsFolder = "Attachments"

        let r = try VaultExporter.export(pf, settings: settings)
        XCTAssertEqual(r.imageCount, 1)
        let md = try String(contentsOf: r.markdownURL, encoding: .utf8)
        XCTAssertTrue(md.contains("![[whiteboard.jpg]]"), "pinned embed under the original name")
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: vault.appendingPathComponent("Attachments/whiteboard.jpg").path))
    }

    // MARK: - Locked notes (synced flag) never reach the plaintext vault

    func testLockedNoteRefusesExportAndWritesNothing() throws {
        let work = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: work) }
        let vault = work.appendingPathComponent("vault")

        let pf = PipelineFile(id: "1", filename: "Secret.m4a", path: "", size: 0, sourceType: .audio)
        pf.enhancedTitle = "Secret Plans"
        pf.sanitised = "Private thoughts."
        pf.locked = true

        var settings = AppSettings.default
        settings.noteFolder = vault.path

        XCTAssertThrowsError(try VaultExporter.export(pf, settings: settings)) { error in
            XCTAssertEqual(error as? VaultExporter.ExportError, .lockedNote)
        }
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: vault.appendingPathComponent("Secret Plans.md").path),
            "a locked note must never land in the vault")
    }

    // MARK: - noteStem: ONE derivation for the exported filename AND memo-link targets

    func testNoteStemMatchesExportedFilenameRules() {
        XCTAssertEqual(VaultExporter.noteStem(title: "Plan: Q3 / Q4", filename: "x.m4a"), "Plan Q3 - Q4")
        XCTAssertEqual(VaultExporter.noteStem(title: nil, filename: "Voice Memo.m4a"), "Voice Memo")
        XCTAssertEqual(VaultExporter.noteStem(title: "", filename: "Voice Memo.m4a"), "Voice Memo")
        XCTAssertEqual(VaultExporter.noteStem(title: "***", filename: ".m4a"), "note")
    }
}
