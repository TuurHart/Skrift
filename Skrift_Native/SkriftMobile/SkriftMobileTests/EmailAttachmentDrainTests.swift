import XCTest
@testable import SkriftMobile

/// Q448 (C142): the phone drain stores a shared email's attachments as note attachments, in
/// attachment order, under the unique `NoteAttachment` filenames; the body gets one marker per file.
@MainActor
final class EmailAttachmentDrainTests: XCTestCase {

    private func tempDir() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("q448-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    private func entry(files: [String]?, names: [String]?, type: String = "text") -> CaptureInboxEntry {
        CaptureInboxEntry(id: UUID(), type: type, url: nil, urlTitle: "Kiln firing schedule", text: "Hi Tuur,",
                          imageFileName: nil, mimeType: nil, annotationText: nil, significance: 0,
                          sharedAt: "2024-10-08T08:15:30Z",
                          emailAttachmentFileNames: files, emailAttachmentNames: names)
    }

    func testBothAttachmentsAreStoredInOrder() async throws {
        let inbox = try tempDir(), recordings = try tempDir()
        try Data("one".utf8).write(to: inbox.appendingPathComponent("emailatt_0"))
        try Data("two".utf8).write(to: inbox.appendingPathComponent("emailatt_1"))
        let memoID = UUID()

        let entries = await CaptureInboxDrainer.storeEmailAttachments(
            entry(files: ["emailatt_0", "emailatt_1"], names: ["schedule.txt", "glaze.csv"]),
            entryDir: inbox, memoID: memoID, into: recordings)

        XCTAssertEqual(entries.map(\.name), ["schedule.txt", "glaze.csv"])
        XCTAssertTrue(entries.allSatisfy { $0.kind == NoteAttachment.Kind.file && $0.filename.contains(memoID.uuidString) })
        XCTAssertEqual(try String(contentsOf: recordings.appendingPathComponent(entries[0].filename), encoding: .utf8), "one")
        XCTAssertEqual(try String(contentsOf: recordings.appendingPathComponent(entries[1].filename), encoding: .utf8), "two")
        XCTAssertEqual(NoteAttachment.appendingMarkers(to: "Thought", entries: entries),
                       "Thought\n\n[[file_001]]\n\n[[file_002]]")
    }

    func testNoAttachmentsOrNotAnEmailStoresNothing() async throws {
        let inbox = try tempDir(), recordings = try tempDir()
        let none = await CaptureInboxDrainer.storeEmailAttachments(
            entry(files: nil, names: nil), entryDir: inbox, memoID: UUID(), into: recordings)
        XCTAssertTrue(none.isEmpty)
        try Data("x".utf8).write(to: inbox.appendingPathComponent("emailatt_0"))
        let notText = await CaptureInboxDrainer.storeEmailAttachments(
            entry(files: ["emailatt_0"], names: ["a.txt"], type: "url"), entryDir: inbox, memoID: UUID(), into: recordings)
        XCTAssertTrue(notText.isEmpty)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: recordings.path).count, 0)
    }

    func testEntryWithoutTheFieldsStillDecodes() throws {
        let json = #"{"id":"\#(UUID().uuidString)","type":"text","significance":0,"sharedAt":"2024-10-08T08:15:30Z"}"#
        let e = try JSONDecoder().decode(CaptureInboxEntry.self, from: Data(json.utf8))
        XCTAssertNil(e.emailAttachmentFileNames)
    }
}
