import XCTest
import SwiftData

/// Q286 (D171, C76, C77): a plain `.md` file imports as a TYPED note: body = the file, title = its
/// first heading, no capture card. A `.md` beside an `Attachments/` folder is still an Apple Notes
/// export (C76), and a `.txt` is still a text capture (D22). The phone half is
/// `MarkdownImportPhoneTests`; both read the one rule `ImportKinds.textRole`.
@MainActor
final class MarkdownImportTests: XCTestCase {

    private func makeContext() throws -> ModelContext {
        ModelContext(try ModelContainer(for: PipelineFile.self,
                                        configurations: ModelConfiguration(isStoredInMemoryOnly: true)))
    }

    private func ingest(_ file: URL, in work: URL) async throws -> PipelineFile {
        let made = try await IngestService(outputDir: work.appendingPathComponent("out"))
            .ingest(localURLs: [file], into: try makeContext())
        return try XCTUnwrap(made.first)
    }

    private func kind(of pf: PipelineFile) -> SourceKind {
        SourceKind.classify(hasBook: false, media: pf.mediaSource, sharedType: nil,
                            isCaptureRow: pf.sourceType == .capture, hasAudio: pf.sourceType == .audio)
    }

    // MARK: - the one rule

    func testTheRuleSeparatesMarkdownFromTxt() {
        XCTAssertEqual(ImportKinds.textRole(forExtension: "md"), .typedNote)
        XCTAssertEqual(ImportKinds.textRole(forExtension: "MARKDOWN"), .typedNote)
        XCTAssertEqual(ImportKinds.textRole(forExtension: "md", hasAttachmentsFolder: true), .appleNote,
                       "an export with its Attachments folder is an Apple Note (C76)")
        XCTAssertEqual(ImportKinds.textRole(forExtension: "txt"), .textCapture)
        XCTAssertEqual(ImportKinds.textRole(forExtension: "txt", hasAttachmentsFolder: true), .textCapture)
        XCTAssertNil(ImportKinds.textRole(forExtension: "pdf"))
    }

    func testTheTitleIsTheFirstHeadingElseTheFileName() {
        XCTAssertEqual(MarkdownImport.title("intro\n\n# Plan for Friday.\n\nbody", fallback: "n"), "Plan for Friday")
        XCTAssertEqual(MarkdownImport.title("no heading here", fallback: "Groceries"), "Groceries")
    }

    // MARK: - the Mac drop

    func testAPlainMarkdownFileIsATypedNote() async throws {
        let work = makeTempDir(); defer { try? FileManager.default.removeItem(at: work) }
        let f = work.appendingPathComponent("friday.md")
        try "# Plan for Friday\n\nBook the table.".write(to: f, atomically: true, encoding: .utf8)

        let pf = try await ingest(f, in: work)

        XCTAssertEqual(pf.sourceType, .note, "a note row, not a capture card")
        XCTAssertEqual(pf.mediaSource, "typed", "the marker Memo.newTyped writes")
        XCTAssertEqual(kind(of: pf), .typedNote, "reads 'Note', not 'Apple Note'")
        XCTAssertEqual(pf.enhancedTitle, "Plan for Friday")
        XCTAssertTrue((pf.transcript ?? "").contains("Book the table."), "the body is the file")
        XCTAssertEqual(pf.transcribeStatus, .done)
        XCTAssertTrue(MemoDate.isUnknown(pf.uploadedAt), "no date inside the file: date-unknown, never the import moment")
    }

    func testAMarkdownFileBesideAttachmentsStaysAnAppleNote() async throws {
        let work = makeTempDir(); defer { try? FileManager.default.removeItem(at: work) }
        let f = work.appendingPathComponent("export.md")
        try "# My Trip\n\nLook: ![](Attachments/IMG_1.png)".write(to: f, atomically: true, encoding: .utf8)
        let att = work.appendingPathComponent("Attachments", isDirectory: true)
        try FileManager.default.createDirectory(at: att, withIntermediateDirectories: true)
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: att.appendingPathComponent("IMG_1.png"))

        let pf = try await ingest(f, in: work)

        XCTAssertEqual(pf.sourceType, .note)
        XCTAssertNil(pf.mediaSource)
        XCTAssertEqual(kind(of: pf), .appleNote, "C76 keeps the export as an Apple Note")
        XCTAssertEqual(pf.enhancedTitle, "My Trip")
    }

    func testATxtFileIsStillATextCapture() async throws {
        let work = makeTempDir(); defer { try? FileManager.default.removeItem(at: work) }
        let f = work.appendingPathComponent("idea.txt")
        try "just words".write(to: f, atomically: true, encoding: .utf8)

        let pf = try await ingest(f, in: work)

        XCTAssertEqual(pf.sourceType, .capture, "D22 stays: .txt is the Text capture")
        XCTAssertNotEqual(pf.mediaSource, "typed")
    }
}
