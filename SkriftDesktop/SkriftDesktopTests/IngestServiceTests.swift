import XCTest
import SwiftData

final class IngestServiceTests: XCTestCase {
    private func makeContext() throws -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: PipelineFile.self, configurations: config)
        return ModelContext(container)
    }

    private func tempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func testIngestMarkdownNote() throws {
        let work = try tempDir(); defer { try? FileManager.default.removeItem(at: work) }
        let noteURL = work.appendingPathComponent("Groceries en het plan.md")
        try "Buy milk and eggs".write(to: noteURL, atomically: true, encoding: .utf8)

        let ctx = try makeContext()
        let created = try IngestService(outputDir: work.appendingPathComponent("out"))
            .ingest(localURLs: [noteURL], into: ctx)

        XCTAssertEqual(created.count, 1)
        let pf = try XCTUnwrap(created.first)
        XCTAssertEqual(pf.sourceType, .note)
        XCTAssertEqual(pf.transcribeStatus, .done)          // notes arrive transcribed
        XCTAssertEqual(pf.transcript, "Buy milk and eggs")
        XCTAssertEqual(pf.filename, "Groceries en het plan.md")
        XCTAssertTrue(pf.path.hasSuffix("original.md"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: pf.path))
    }

    func testIngestAudioCopiesIntoPerFileFolder() throws {
        let work = try tempDir(); defer { try? FileManager.default.removeItem(at: work) }
        let audioURL = work.appendingPathComponent("Voice Memo 09-14.m4a")
        try Data([0x00, 0x01, 0x02, 0x03]).write(to: audioURL)

        let ctx = try makeContext()
        let created = try IngestService(outputDir: work.appendingPathComponent("out"))
            .ingest(localURLs: [audioURL], into: ctx)

        let pf = try XCTUnwrap(created.first)
        XCTAssertEqual(pf.sourceType, .audio)
        XCTAssertNotEqual(pf.transcribeStatus, .done)        // audio still needs transcription
        XCTAssertEqual(pf.size, 4)
        XCTAssertTrue(pf.path.hasSuffix("original.m4a"))
        XCTAssertTrue(pf.path.contains("\(pf.id)_Voice Memo 09-14.m4a"))   // per-file folder
        XCTAssertTrue(FileManager.default.fileExists(atPath: pf.path))
    }

    func testUnsupportedTypeSkipped() throws {
        let work = try tempDir(); defer { try? FileManager.default.removeItem(at: work) }
        let pdf = work.appendingPathComponent("doc.pdf")
        try Data([0x25, 0x50, 0x44, 0x46]).write(to: pdf)   // %PDF

        let ctx = try makeContext()
        let created = try IngestService(outputDir: work.appendingPathComponent("out"))
            .ingest(localURLs: [pdf], into: ctx)

        XCTAssertTrue(created.isEmpty)
    }

    func testIngestFolderOfNotes() throws {
        let work = try tempDir(); defer { try? FileManager.default.removeItem(at: work) }
        let notes = work.appendingPathComponent("AppleNotesExport", isDirectory: true)
        try FileManager.default.createDirectory(at: notes, withIntermediateDirectories: true)
        try "Note one".write(to: notes.appendingPathComponent("a.md"), atomically: true, encoding: .utf8)
        try "Note two".write(to: notes.appendingPathComponent("b.md"), atomically: true, encoding: .utf8)
        try "ignore".write(to: notes.appendingPathComponent("c.txt"), atomically: true, encoding: .utf8)

        let ctx = try makeContext()
        let created = try IngestService(outputDir: work.appendingPathComponent("out"))
            .ingest(localURLs: [notes], into: ctx)

        XCTAssertEqual(created.count, 2)
        XCTAssertTrue(created.allSatisfy { $0.sourceType == .note })
    }

    func testSanitizeTitle() {
        XCTAssertEqual(IngestService.sanitizeTitle("a/b:c"), "a-b-c")        // illegal → "-"
        XCTAssertEqual(IngestService.sanitizeTitle("  hi  there  "), "hi there")  // whitespace collapsed + trimmed
        XCTAssertEqual(IngestService.sanitizeTitle("////"), "note")          // all illegal → empty → fallback
    }

    func testIngestNoteImportsAndRenamesAttachment() throws {
        let work = try tempDir(); defer { try? FileManager.default.removeItem(at: work) }
        let noteURL = work.appendingPathComponent("export.md")
        try "# My Trip\n\nLook: ![](Attachments/IMG_1.png)".write(to: noteURL, atomically: true, encoding: .utf8)
        let srcAtt = work.appendingPathComponent("Attachments", isDirectory: true)
        try FileManager.default.createDirectory(at: srcAtt, withIntermediateDirectories: true)
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: srcAtt.appendingPathComponent("IMG_1.png"))

        let ctx = try makeContext()
        let created = try IngestService(outputDir: work.appendingPathComponent("out"))
            .ingest(localURLs: [noteURL], into: ctx)

        let pf = try XCTUnwrap(created.first)
        XCTAssertTrue((pf.transcript ?? "").contains("(Attachments/My Trip - 1.png)"), "ref rewritten to safe name")
        XCTAssertFalse((pf.transcript ?? "").contains("IMG_1.png"), "old ref replaced")

        let noteFolder = URL(fileURLWithPath: pf.path).deletingLastPathComponent()
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: noteFolder.appendingPathComponent("Attachments/My Trip - 1.png").path),
            "attachment copied + renamed into the note folder")
        XCTAssertTrue(FileManager.default.fileExists(atPath: srcAtt.appendingPathComponent("IMG_1.png").path),
            "source export left untouched (copy, not move)")
    }

    func testIngestNoteParsesHeadingTitle() throws {
        let work = try tempDir(); defer { try? FileManager.default.removeItem(at: work) }
        let noteURL = work.appendingPathComponent("export-2026-06-07.md")
        try "# Hotel du Vin plan\n\nBook the table for Friday.".write(to: noteURL, atomically: true, encoding: .utf8)

        let ctx = try makeContext()
        let created = try IngestService(outputDir: work.appendingPathComponent("out"))
            .ingest(localURLs: [noteURL], into: ctx)

        let pf = try XCTUnwrap(created.first)
        XCTAssertEqual(pf.enhancedTitle, "Hotel du Vin plan")        // from the # heading, not the filename
        XCTAssertTrue((pf.transcript ?? "").contains("Book the table"))
    }
}
