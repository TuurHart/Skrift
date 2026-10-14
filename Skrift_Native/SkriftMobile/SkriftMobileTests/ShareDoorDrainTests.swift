import XCTest
@testable import SkriftMobile

/// Q440: the phone side of the share doors. C126 a one-clip share keeps the clip's own name
/// (never the drain's temp-copy name, never a messenger name); C127 the share ledger drops rows
/// whose note is gone; C146 a shared book goes to the Books importer, never a note or a file card.
final class ShareDoorDrainTests: XCTestCase {

    @MainActor
    private func cleanInbox() throws {
        guard let inbox = CaptureInbox.inboxURL else { throw XCTSkip("no App Group container in this test host") }
        try? FileManager.default.removeItem(at: inbox)
    }

    private func tempFile(_ ext: String, _ bytes: String = "AAC-ish") -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("q440_\(UUID().uuidString).\(ext)")
        FileManager.default.createFile(atPath: url.path, contents: Data(bytes.utf8))
        return url
    }

    private func audioEntry(id: UUID, original: String) -> CaptureInboxEntry {
        CaptureInboxEntry(
            id: id, type: "audio", url: nil, urlTitle: nil, text: nil,
            imageFileName: nil, mimeType: nil, annotationText: nil,
            significance: 0, sharedAt: ISO8601.string(from: Date()),
            audioFileNames: ["audio_\(id.uuidString)_0.m4a"], audioOriginalNames: [original])
    }

    /// C126: the clip's original name decides; a messenger name and a combine get "".
    @MainActor
    func testClipFileNameRule() {
        let id = UUID()
        XCTAssertEqual(CaptureInboxDrainer.clipFileName(audioEntry(id: id, original: "kiln idea.m4a")), "kiln idea.m4a")
        XCTAssertEqual(CaptureInboxDrainer.clipFileName(audioEntry(id: id, original: "PTT-20241003-WA0007.opus")), "")
        XCTAssertEqual(CaptureInboxDrainer.clipFileName(audioEntry(id: id, original: "")), "")
        var two = audioEntry(id: id, original: "kiln idea.m4a")
        two.audioFileNames = ["a.m4a", "b.m4a"]
        XCTAssertEqual(CaptureInboxDrainer.clipFileName(two), "", "two clips, one note: no single name")
    }

    /// C126 end to end: a Voice Memo named "kiln idea" titles its note by that name; a WhatsApp
    /// clip's note keeps no import name (before Q440 it took the temp copy's `shared_import_…`).
    @MainActor
    func testDrainKeepsTheVoiceMemoNameAndDropsTheMessengerName() async throws {
        try cleanInbox()
        let repo = NotesRepository(inMemory: true)
        let named = UUID(), messenger = UUID()
        let src1 = tempFile("m4a"), src2 = tempFile("m4a")
        XCTAssertTrue(CaptureInbox.write(audioEntry(id: named, original: "kiln idea.m4a"), audioFileURLs: [src1]))
        XCTAssertTrue(CaptureInbox.write(audioEntry(id: messenger, original: "PTT-20241003-WA0007.opus"), audioFileURLs: [src2]))

        await CaptureInboxDrainer.drain(into: repo)

        XCTAssertEqual(repo.memo(id: named)?.metadata?.importFileName, "kiln idea", "stored without the extension (D176)")
        XCTAssertNotNil(repo.memo(id: messenger))
        XCTAssertNil(repo.memo(id: messenger)?.metadata?.importFileName, "a messenger name is never a title")
        _ = MemoOpenBridge.shared.consume()
        for m in repo.allMemos() { if let f = m.audioURL { try? FileManager.default.removeItem(at: f) } }
    }

    /// C127: after a drain, a ledger row whose note does not exist is gone; a live note's stays.
    @MainActor
    func testDrainPrunesLedgerRowsWithoutANote() async throws {
        try cleanInbox()
        let ledger = try XCTUnwrap(ShareLedger.inContainer(CaptureInbox.containerURL))
        let repo = NotesRepository(inMemory: true)
        let live = UUID()
        let src = tempFile("m4a")
        XCTAssertTrue(CaptureInbox.write(audioEntry(id: live, original: "kiln idea.m4a"), audioFileURLs: [src]))
        ledger.record("fp-live-\(live)", id: live)
        ledger.record("fp-gone-\(live)", id: UUID())

        await CaptureInboxDrainer.drain(into: repo)

        XCTAssertEqual(ledger.existing("fp-live-\(live)"), live)
        XCTAssertNil(ledger.existing("fp-gone-\(live)"), "a deleted note's bytes can be shared in again")
        _ = MemoOpenBridge.shared.consume()
        for m in repo.allMemos() { if let f = m.audioURL { try? FileManager.default.removeItem(at: f) } }
    }

    /// C146: a "book" entry makes no note; the book importer gets the file and Books comes forward.
    @MainActor
    func testBookEntryGoesToTheBookImporter() async throws {
        try cleanInbox()
        let repo = NotesRepository(inMemory: true)
        let id = UUID()
        let ext = BookBundle.fileExtension
        let src = tempFile(ext, "not really a zip")
        let entry = CaptureInboxEntry(
            id: id, type: "book", url: nil, urlTitle: nil, text: nil, imageFileName: nil, mimeType: nil,
            annotationText: nil, significance: 0, sharedAt: ISO8601.string(from: Date()),
            fileName: "book_\(id.uuidString).\(ext)", fileDisplayName: "The Potter's Year.\(ext)")
        XCTAssertTrue(CaptureInbox.write(entry, fileSourceURL: src))
        BookImportBridge.shared.pending = nil
        BookImportBridge.shared.failure = nil

        await CaptureInboxDrainer.drain(into: repo)

        XCTAssertTrue(repo.allMemos().isEmpty, "a book is never a note or a file card")
        XCTAssertTrue(CaptureInbox.pendingEntries().isEmpty, "entry consumed")
        XCTAssertTrue(BookImportBridge.shared.pending != nil || BookImportBridge.shared.failure != nil,
                      "the book importer was handed the file")
        XCTAssertEqual(TabSelectionBridge.shared.requestedTab, .books)
        BookImportBridge.shared.failure = nil
        TabSelectionBridge.shared.requestedTab = nil
        try? FileManager.default.removeItem(at: src)
    }
}
