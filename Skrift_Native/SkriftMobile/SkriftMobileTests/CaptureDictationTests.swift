import XCTest
@testable import SkriftMobile

final class CaptureDictationTests: XCTestCase {

    /// Drain a shared-document (.file) entry: the PDF is copied into the recordings
    /// dir, the capture memo carries `sharedContent.type == .file` with a resolvable
    /// `sharedFileURL`, and the inbox entry is consumed. (2026-06-21 PDF share-import.)
    @MainActor
    func testDrainPersistsSharedFileCapture() async throws {
        let repo = NotesRepository(inMemory: true)
        guard let inbox = CaptureInbox.inboxURL else {
            throw XCTSkip("no App Group container in this test host")
        }
        try? FileManager.default.removeItem(at: inbox)

        let id = UUID()
        let entry = CaptureInboxEntry(
            id: id, type: "file", url: nil, urlTitle: nil, text: nil,
            imageFileName: nil, mimeType: "application/pdf",
            annotationText: nil, significance: 0,
            sharedAt: ISO8601.string(from: Date()),
            fileName: "file_\(id.uuidString).pdf",
            fileDisplayName: "report.pdf")
        let src = FileManager.default.temporaryDirectory.appendingPathComponent("src_\(UUID().uuidString).pdf")
        FileManager.default.createFile(atPath: src.path, contents: Data("%PDF-1.4".utf8))
        XCTAssertTrue(CaptureInbox.write(entry, fileSourceURL: src))

        await CaptureInboxDrainer.drain(into: repo)

        let memo = repo.memo(id: id)
        XCTAssertEqual(memo?.sharedContent?.type, .file)
        XCTAssertEqual(memo?.sharedContent?.fileName, "report.pdf")
        XCTAssertEqual(memo?.transcriptStatus, .done)   // a capture needs no ASR → done immediately
        let fileURL = try XCTUnwrap(memo?.sharedFileURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path), "the document is persisted in recordings")
        XCTAssertTrue(CaptureInbox.pendingEntries().isEmpty, "entry consumed")
        try? FileManager.default.removeItem(at: fileURL)
        try? FileManager.default.removeItem(at: src)
    }

    /// Old inbox entries (written before dictation existed) still decode.
    func testEntryWithoutDictationFieldDecodes() throws {
        let legacyJSON = """
        {"id":"6E1AD320-DC78-4B28-8DF7-52BDB461A324","type":"url","url":"https://a.com",
        "urlTitle":"A","text":null,"imageFileName":null,"mimeType":null,
        "annotationText":"x","significance":0.3,"sharedAt":"2026-06-12T10:00:00.000Z"}
        """
        let entry = try JSONDecoder().decode(CaptureInboxEntry.self, from: Data(legacyJSON.utf8))
        XCTAssertEqual(entry.annotationText, "x")
    }

    /// A pre-build-63 pending entry still carries `dictationFileName`; the field is gone
    /// from the model, and Codable must ignore the unknown key rather than skip the entry.
    func testEntryWithRetiredDictationKeyStillDecodes() throws {
        let json = """
        {"id":"6E1AD320-DC78-4B28-8DF7-52BDB461A324","type":"url","url":"https://a.com",
        "urlTitle":"A","text":null,"imageFileName":null,"mimeType":null,
        "annotationText":"x","significance":0.3,"sharedAt":"2026-06-12T10:00:00.000Z",
        "dictationFileName":"dictation.m4a"}
        """
        let entry = try JSONDecoder().decode(CaptureInboxEntry.self, from: Data(json.utf8))
        XCTAssertEqual(entry.url, "https://a.com")
    }
}
