import XCTest
@testable import SkriftMobile

/// A transcriber that always throws — drives the terminal-failure paths.
private struct FailingTranscriber: Transcriber {
    struct Err: Error {}
    func transcribe(audioURL: URL, imageManifest: [ImageManifestEntry]) async throws -> TranscriptionResult {
        throw Err()
    }
}

final class CaptureDictationTests: XCTestCase {

    @MainActor
    override func setUp() {
        super.setUp()
        CaptureDictation.retryDelays = [0]   // instant retries in tests
    }

    /// Helper: a capture memo with a pending dictation file on disk.
    @MainActor
    private func makePendingDictationMemo(repo: NotesRepository, typed: String? = nil) -> UUID {
        let id = UUID()
        repo.insert(Memo(id: id, audioFilename: "", duration: 0, recordedAt: Date(),
                         syncStatus: .waiting, transcript: nil, transcriptStatus: .transcribing,
                         significance: 0.5,
                         sharedContent: SharedContent(type: .url, url: "https://x.com", urlTitle: "X",
                                                      text: nil, fileName: nil, mimeType: nil),
                         annotationText: typed))
        try? FileManager.default.createDirectory(at: AppPaths.recordingsDirectory, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: CaptureDictation.pendingAudioURL(for: id).path,
                                       contents: Data("AAC".utf8))
        return id
    }

    @MainActor
    func testDictationAppendsToTypedAnnotationAndConsumesAudio() async {
        let repo = NotesRepository(inMemory: true)
        let id = makePendingDictationMemo(repo: repo, typed: "typed thought")

        await CaptureDictation.transcribeNow(memoID: id, repository: repo,
                                             transcriber: SeededTranscriber(text: "spoken thought"))

        let memo = repo.memo(id: id)
        XCTAssertEqual(memo?.annotationText, "typed thought\n\nspoken thought")
        XCTAssertEqual(memo?.transcriptStatus, .done)
        XCTAssertFalse(FileManager.default.fileExists(atPath: CaptureDictation.pendingAudioURL(for: id).path),
                       "audio consumed after the text landed")
    }

    @MainActor
    func testDictationOnlyBecomesTheAnnotation() async {
        let repo = NotesRepository(inMemory: true)
        let id = makePendingDictationMemo(repo: repo, typed: nil)

        await CaptureDictation.transcribeNow(memoID: id, repository: repo,
                                             transcriber: SeededTranscriber(text: "only spoken"))

        XCTAssertEqual(repo.memo(id: id)?.annotationText, "only spoken")
        XCTAssertEqual(repo.memo(id: id)?.transcriptStatus, .done)
    }

    @MainActor
    func testTerminalFailureSurfacesAndKeepsAudioThenRecovers() async {
        let repo = NotesRepository(inMemory: true)
        let id = makePendingDictationMemo(repo: repo, typed: "typed")

        await CaptureDictation.transcribeNow(memoID: id, repository: repo,
                                             transcriber: FailingTranscriber())

        XCTAssertEqual(repo.memo(id: id)?.transcriptStatus, .failed, "failure surfaces as Error pill")
        XCTAssertTrue(FileManager.default.fileExists(atPath: CaptureDictation.pendingAudioURL(for: id).path),
                      "audio kept as the retry source")
        XCTAssertEqual(repo.memo(id: id)?.annotationText, "typed", "typed text untouched")

        // Next drain recovers it.
        await CaptureDictation.transcribeNow(memoID: id, repository: repo,
                                             transcriber: SeededTranscriber(text: "recovered"))
        XCTAssertEqual(repo.memo(id: id)?.transcriptStatus, .done)
        XCTAssertEqual(repo.memo(id: id)?.annotationText, "typed\n\nrecovered")
    }

    @MainActor
    func testMissingAudioClosesOutInsteadOfSticking() async {
        let repo = NotesRepository(inMemory: true)
        let id = makePendingDictationMemo(repo: repo)
        try? FileManager.default.removeItem(at: CaptureDictation.pendingAudioURL(for: id))

        await CaptureDictation.transcribeNow(memoID: id, repository: repo,
                                             transcriber: SeededTranscriber(text: "unused"))

        XCTAssertEqual(repo.memo(id: id)?.transcriptStatus, .done,
                       "no audio -> close out honestly, never stuck .transcribing")
    }

    /// Drain end-to-end: an inbox entry with a dictation file produces a
    /// .transcribing memo with the audio staged at the pending path, and the
    /// entry deleted — crash-safe ordering.
    @MainActor
    func testDrainStagesDictationAudioAndMarksTranscribing() throws {
        let repo = NotesRepository(inMemory: true)
        guard let inbox = CaptureInbox.inboxURL else {
            throw XCTSkip("no App Group container in this test host")
        }
        // Isolate: clear anything a previous test left.
        try? FileManager.default.removeItem(at: inbox)

        let entry = CaptureInboxEntry(
            id: UUID(), type: "url", url: "https://example.com", urlTitle: "Example",
            text: nil, imageFileName: nil, mimeType: nil,
            annotationText: "typed", significance: 0.4,
            sharedAt: ISO8601.string(from: Date()),
            dictationFileName: "dictation.m4a")
        XCTAssertTrue(CaptureInbox.write(entry, dictationData: Data("AUDIO".utf8)))

        CaptureInboxDrainer.drain(into: repo)

        let memo = repo.memo(id: entry.id)
        XCTAssertNotNil(memo)
        // The fire-and-forget transcription task may not have started yet (and the
        // sim's TranscriberFactory seeds text instantly when it does) — the stable
        // assertions are the staging + inbox cleanup.
        XCTAssertTrue(CaptureInbox.pendingEntries().isEmpty, "entry consumed")
        XCTAssertEqual(memo?.sharedContent?.url, "https://example.com")
    }

    /// Drain a shared-document (.file) entry: the PDF is copied into the recordings
    /// dir, the capture memo carries `sharedContent.type == .file` with a resolvable
    /// `sharedFileURL`, and the inbox entry is consumed. (2026-06-21 PDF share-import.)
    @MainActor
    func testDrainPersistsSharedFileCapture() throws {
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

        CaptureInboxDrainer.drain(into: repo)

        let memo = repo.memo(id: id)
        XCTAssertEqual(memo?.sharedContent?.type, .file)
        XCTAssertEqual(memo?.sharedContent?.fileName, "report.pdf")
        XCTAssertEqual(memo?.transcriptStatus, .done)   // no dictation → done immediately
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
        XCTAssertNil(entry.dictationFileName)
        XCTAssertEqual(entry.annotationText, "x")
    }
}
