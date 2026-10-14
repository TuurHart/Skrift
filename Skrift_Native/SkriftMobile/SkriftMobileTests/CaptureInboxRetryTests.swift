import XCTest
@testable import SkriftMobile

/// Q414 / C147 / C271 / R84: a capture-inbox entry is deleted only after the memo it made is
/// saved. A failed import keeps the entry for the next drain, and a re-drain is idempotent (the
/// memo carries the entry's id), for every capture type.
final class CaptureInboxRetryTests: XCTestCase {

    struct ImportFailed: Error {}

    override func tearDown() async throws {
        await MainActor.run {
            CaptureInboxDrainer.beforeImport = { _ in }
            _ = MemoOpenBridge.shared.consume()
            if let inbox = CaptureInbox.inboxURL { try? FileManager.default.removeItem(at: inbox) }
        }
    }

    @MainActor
    private func cleanInbox() throws {
        guard let inbox = CaptureInbox.inboxURL else {
            throw XCTSkip("no App Group container in this test host")
        }
        try? FileManager.default.removeItem(at: inbox)
    }

    private func makeFile(_ ext: String) -> URL {
        let src = FileManager.default.temporaryDirectory
            .appendingPathComponent("retry_src_\(UUID().uuidString).\(ext)")
        FileManager.default.createFile(atPath: src.path, contents: Data("not-really-media".utf8))
        return src
    }

    /// Drain once with an import that throws, check nothing was lost, then drain again.
    @MainActor
    private func assertRetried(_ entry: CaptureInboxEntry, write: () -> Bool,
                               file: StaticString = #filePath, line: UInt = #line) async throws {
        try cleanInbox()
        let repo = NotesRepository(inMemory: true)
        XCTAssertTrue(write(), "entry written", file: file, line: line)

        CaptureInboxDrainer.beforeImport = { _ in throw ImportFailed() }
        await CaptureInboxDrainer.drain(into: repo)
        XCTAssertEqual(CaptureInbox.pendingEntries().map(\.entry.id), [entry.id],
                       "\(entry.type): a failed import keeps the entry", file: file, line: line)
        XCTAssertTrue(repo.allMemosIncludingTrashed().isEmpty,
                      "\(entry.type): no note from a failed import", file: file, line: line)

        CaptureInboxDrainer.beforeImport = { _ in }
        await CaptureInboxDrainer.drain(into: repo)
        XCTAssertTrue(CaptureInbox.pendingEntries().isEmpty,
                      "\(entry.type): the retry consumes the entry", file: file, line: line)
        let memos = repo.allMemosIncludingTrashed()
        XCTAssertEqual(memos.count, 1, "\(entry.type): the retry makes exactly one note", file: file, line: line)
        XCTAssertEqual(memos.first?.id, entry.id, "\(entry.type): the note carries the entry id",
                       file: file, line: line)

        // Re-drain after a kill between the save and the delete: the same entry back in the
        // inbox must not make a second note.
        XCTAssertTrue(write(), "entry re-written", file: file, line: line)
        await CaptureInboxDrainer.drain(into: repo)
        XCTAssertTrue(CaptureInbox.pendingEntries().isEmpty,
                      "\(entry.type): the re-drain removes the entry", file: file, line: line)
        XCTAssertEqual(repo.allMemosIncludingTrashed().count, 1,
                       "\(entry.type): the re-drain is idempotent", file: file, line: line)
    }

    @MainActor
    func testAudioImportThatThrowsKeepsTheEntry() async throws {
        let id = UUID()
        let entry = CaptureInboxEntry(
            id: id, type: "audio", url: nil, urlTitle: nil, text: nil,
            imageFileName: nil, mimeType: nil, annotationText: nil,
            significance: 0.3, sharedAt: ISO8601.string(from: Date()),
            audioFileNames: ["audio_\(id.uuidString)_0.m4a"])
        let src = makeFile("m4a")
        defer { try? FileManager.default.removeItem(at: src) }
        try await assertRetried(entry) { CaptureInbox.write(entry, audioFileURLs: [src]) }
    }

    @MainActor
    func testCombinedAudioImportThatThrowsKeepsTheEntry() async throws {
        let id = UUID()
        let entry = CaptureInboxEntry(
            id: id, type: "audio", url: nil, urlTitle: nil, text: nil,
            imageFileName: nil, mimeType: nil, annotationText: nil,
            significance: 0.3, sharedAt: ISO8601.string(from: Date()),
            audioFileNames: ["audio_\(id.uuidString)_0.m4a", "audio_\(id.uuidString)_1.m4a"])
        let srcs = [makeFile("m4a"), makeFile("m4a")]
        defer { srcs.forEach { try? FileManager.default.removeItem(at: $0) } }
        try await assertRetried(entry) { CaptureInbox.write(entry, audioFileURLs: srcs) }
    }

    @MainActor
    func testVideoImportThatThrowsKeepsTheEntry() async throws {
        let id = UUID()
        let entry = CaptureInboxEntry(
            id: id, type: "video", url: nil, urlTitle: nil, text: nil,
            imageFileName: nil, mimeType: nil, annotationText: "a thought",
            significance: 0.5, sharedAt: ISO8601.string(from: Date()),
            videoFileName: "video_\(id.uuidString).mov")
        let src = makeFile("mov")
        defer { try? FileManager.default.removeItem(at: src) }
        try await assertRetried(entry) { CaptureInbox.write(entry, videoFileURL: src) }
    }

    @MainActor
    func testTextImportThatThrowsKeepsTheEntry() async throws {
        let entry = CaptureInboxEntry(
            id: UUID(), type: "text", url: nil, urlTitle: nil, text: "keep me",
            imageFileName: nil, mimeType: nil, annotationText: nil,
            significance: 0.2, sharedAt: ISO8601.string(from: Date()))
        try await assertRetried(entry) { CaptureInbox.write(entry) }
    }
}
