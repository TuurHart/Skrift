import XCTest
@testable import SkriftMobile

/// Q286 (D171, C76, C77): a shared `.md` file becomes a TYPED note on the phone: body = the file,
/// title = its first heading, no capture card. A `.txt` stays a Text capture (D22). The Mac half is
/// `MarkdownImportTests`; both read the one rule `ImportKinds.textRole`.
final class MarkdownImportPhoneTests: XCTestCase {

    // MARK: - the note a .md becomes

    @MainActor func testTypedNoteShape() {
        let id = UUID()
        let memo = CaptureInboxDrainer.typedNoteMemo(
            id: id, markdown: "# Plan for Friday\n\nBook the table.", fileName: "friday.md",
            thought: nil, significance: 0)

        XCTAssertEqual(memo.id, id)
        XCTAssertEqual(memo.title, "Plan for Friday", "title = the first heading")
        XCTAssertEqual(memo.transcript, "# Plan for Friday\n\nBook the table.", "body = the file")
        XCTAssertEqual(memo.transcriptStatus, .done)
        XCTAssertNil(memo.sharedContent, "no capture card")
        XCTAssertEqual(memo.audioFilename, "")
        XCTAssertEqual(SourceKind.of(memo), .typedNote, "reads 'Note', like a note typed in the app")
        XCTAssertTrue(MemoDate.isUnknown(memo.recordedAt), "no date in the file: date-unknown, not the import moment")
    }

    @MainActor func testTitleFallsBackToTheFileNameAndAThoughtLeadsTheBody() {
        let memo = CaptureInboxDrainer.typedNoteMemo(
            id: UUID(), markdown: "just words", fileName: "Groceries.md",
            thought: "  for tonight ", significance: 0.4)
        XCTAssertEqual(memo.title, "Groceries")
        XCTAssertEqual(memo.transcript, "for tonight\n\njust words")
        XCTAssertEqual(memo.significance, 0.4, accuracy: 0.001)
    }

    @MainActor func testACreationDateInsideTheFileDatesTheNote() {
        let memo = CaptureInboxDrainer.typedNoteMemo(
            id: UUID(), markdown: "---\ncreated: 2026-05-06\n---\n# T\n\nbody", fileName: "t.md",
            thought: nil, significance: 0)
        XCTAssertFalse(MemoDate.isUnknown(memo.recordedAt))
        XCTAssertEqual(memo.recordedAt, MarkdownImport.creationDate("created: 2026-05-06"))
    }

    // MARK: - the drain

    @MainActor
    private func cleanInbox() throws {
        guard let inbox = CaptureInbox.inboxURL else {
            throw XCTSkip("no App Group container in this test host")
        }
        try? FileManager.default.removeItem(at: inbox)
    }

    @MainActor
    private func drainFile(named display: String, body: String, into repo: NotesRepository) async throws -> Memo {
        try cleanInbox()
        let id = UUID()
        let ext = (display as NSString).pathExtension
        let entry = CaptureInboxEntry(
            id: id, type: "file", url: nil, urlTitle: nil, text: nil,
            imageFileName: nil, mimeType: nil, annotationText: nil, significance: 0,
            sharedAt: ISO8601.string(from: Date()),
            fileName: "file_\(id.uuidString).\(ext)", fileDisplayName: display)
        let src = FileManager.default.temporaryDirectory.appendingPathComponent("src_\(UUID().uuidString).\(ext)")
        try Data(body.utf8).write(to: src)
        defer { try? FileManager.default.removeItem(at: src) }
        XCTAssertTrue(CaptureInbox.write(entry, fileSourceURL: src))

        await CaptureInboxDrainer.drain(into: repo)

        XCTAssertTrue(CaptureInbox.pendingEntries().isEmpty, "entry consumed")
        _ = MemoOpenBridge.shared.consume()
        return try XCTUnwrap(repo.memo(id: id))
    }

    @MainActor
    func testASharedMarkdownFileDrainsToATypedNote() async throws {
        let repo = NotesRepository(inMemory: true)   // must outlive the memo: a freed context traps
        let memo = try await drainFile(named: "Friday.md", body: "# Plan for Friday\n\nBook the table.", into: repo)
        XCTAssertEqual(SourceKind.of(memo), .typedNote)
        XCTAssertNil(memo.sharedContent, "no Text capture card")
        XCTAssertEqual(memo.title, "Plan for Friday")
        XCTAssertTrue((memo.transcript ?? "").contains("Book the table."))
    }

    @MainActor
    func testASharedTxtFileStaysATextCapture() async throws {
        let repo = NotesRepository(inMemory: true)
        let memo = try await drainFile(named: "idea.txt", body: "just words", into: repo)
        XCTAssertEqual(SourceKind.of(memo), .captureText, "D22 stays")
        XCTAssertEqual(memo.sharedContent?.type, .text)
        XCTAssertTrue((memo.annotationText ?? "").contains("just words"))
    }
}
