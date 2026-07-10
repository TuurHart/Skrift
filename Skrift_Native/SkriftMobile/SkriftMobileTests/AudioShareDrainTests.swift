import XCTest
@testable import SkriftMobile

/// Drain-side coverage for the `"audio"` inbox entries the share extension writes
/// (Wave-1 A7 — the i4 "WhatsApp voice note became a LINK" fix, mock
/// `share-ingest-wave1.html` signed 2026-07-10). The loader half (audio branch
/// BEFORE url in `SharePayloadLoader`) lives in the extension target and isn't
/// linkable here — the device round covers it with a real WhatsApp share.
final class AudioShareDrainTests: XCTestCase {

    /// An "audio" entry drains into a normal transcribed memo (audioFilename set —
    /// NOT a capture item), carries the sheet's significance, consumes the inbox
    /// entry, and requests the jump-to-note (every share opens on next app-open).
    @MainActor
    func testDrainImportsSharedAudioAsTranscribedMemo() throws {
        let repo = NotesRepository(inMemory: true)
        guard let inbox = CaptureInbox.inboxURL else {
            throw XCTSkip("no App Group container in this test host")
        }
        try? FileManager.default.removeItem(at: inbox)

        let id = UUID()
        let entry = CaptureInboxEntry(
            id: id, type: "audio", url: nil, urlTitle: nil, text: nil,
            imageFileName: nil, mimeType: nil, annotationText: nil,
            significance: 0.4, sharedAt: ISO8601.string(from: Date()),
            audioFileName: "audio_\(id.uuidString).m4a")
        let src = FileManager.default.temporaryDirectory
            .appendingPathComponent("src_\(UUID().uuidString).m4a")
        FileManager.default.createFile(atPath: src.path, contents: Data("AAC-ish".utf8))
        XCTAssertTrue(CaptureInbox.write(entry, audioFileURL: src))

        CaptureInboxDrainer.drain(into: repo)

        XCTAssertTrue(CaptureInbox.pendingEntries().isEmpty, "entry consumed")
        // importAudio mints its own memo UUID — find it by the audio-memo shape.
        let imported = repo.allMemos().first { $0.audioFilename.hasPrefix("memo_") }
        XCTAssertNotNil(imported, "audio share becomes a normal memo, not a capture card")
        XCTAssertEqual(imported?.significance ?? 0, 0.4, accuracy: 0.001,
                       "sheet significance lands on the imported memo")
        XCTAssertEqual(MemoOpenBridge.shared.consume(), imported?.id,
                       "share requests the jump-to-note")

        if let f = imported?.audioURL { try? FileManager.default.removeItem(at: f) }
        try? FileManager.default.removeItem(at: src)
    }

    /// An audio entry whose payload file vanished (failed inbox copy) is discarded
    /// rather than looping forever — and creates no memo.
    @MainActor
    func testAudioEntryWithoutFileIsDiscarded() throws {
        let repo = NotesRepository(inMemory: true)
        guard let inbox = CaptureInbox.inboxURL else {
            throw XCTSkip("no App Group container in this test host")
        }
        try? FileManager.default.removeItem(at: inbox)

        let id = UUID()
        let entry = CaptureInboxEntry(
            id: id, type: "audio", url: nil, urlTitle: nil, text: nil,
            imageFileName: nil, mimeType: nil, annotationText: nil,
            significance: 0, sharedAt: ISO8601.string(from: Date()),
            audioFileName: "audio_\(id.uuidString).m4a")
        XCTAssertTrue(CaptureInbox.write(entry))   // no audioFileURL → no payload file

        CaptureInboxDrainer.drain(into: repo)

        XCTAssertTrue(CaptureInbox.pendingEntries().isEmpty, "husk entry discarded")
        XCTAssertTrue(repo.allMemos().isEmpty, "no memo minted for a lost payload")
    }

    /// The signed jump-on-open rule covers plain captures too: a url capture's
    /// drain requests opening the new capture memo.
    @MainActor
    func testCaptureDrainAlsoRequestsJumpToNote() throws {
        let repo = NotesRepository(inMemory: true)
        guard let inbox = CaptureInbox.inboxURL else {
            throw XCTSkip("no App Group container in this test host")
        }
        try? FileManager.default.removeItem(at: inbox)

        let entry = CaptureInboxEntry(
            id: UUID(), type: "url", url: "https://example.com", urlTitle: "Example",
            text: nil, imageFileName: nil, mimeType: nil,
            annotationText: nil, significance: 0,
            sharedAt: ISO8601.string(from: Date()))
        XCTAssertTrue(CaptureInbox.write(entry))

        CaptureInboxDrainer.drain(into: repo)

        XCTAssertEqual(MemoOpenBridge.shared.consume(), entry.id,
                       "every share type jumps to its note on next open")
    }

    /// Old inbox entries (written before audio shares existed) still decode.
    func testEntryWithoutAudioFieldDecodes() throws {
        let legacyJSON = """
        {"id":"6E1AD320-DC78-4B28-8DF7-52BDB461A324","type":"url","url":"https://a.com",
        "urlTitle":"A","text":null,"imageFileName":null,"mimeType":null,
        "annotationText":"x","significance":0.3,"sharedAt":"2026-06-12T10:00:00.000Z"}
        """
        let entry = try JSONDecoder().decode(CaptureInboxEntry.self, from: Data(legacyJSON.utf8))
        XCTAssertNil(entry.audioFileName)
        XCTAssertEqual(entry.type, "url")
    }
}
