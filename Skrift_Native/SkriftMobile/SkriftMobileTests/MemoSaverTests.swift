import XCTest
@testable import SkriftMobile

final class MemoSaverTests: XCTestCase {

    @MainActor
    func testSaveAndTranscribeFillsMemoAndSidecar() async {
        let repo = NotesRepository(inMemory: true)
        let sidecarDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("wt_\(UUID().uuidString)", isDirectory: true)
        let saver = MemoSaver(
            repository: repo,
            transcriber: SeededTranscriber(text: "hello world from skrift"),
            wordTimings: WordTimingsStore(directory: sidecarDir),
            metadataProvider: MockMetadataService()
        )

        // A placeholder temp audio file for the save to move into place.
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("rec_\(UUID().uuidString).m4a")
        FileManager.default.createFile(atPath: temp.path, contents: Data())

        let id = await saver.saveAndTranscribe(tempURL: temp, duration: 3.2)

        let memo = repo.memo(id: id)
        XCTAssertNotNil(memo)
        XCTAssertEqual(memo?.transcript, "hello world from skrift")
        XCTAssertEqual(memo?.transcriptStatus, .done)
        XCTAssertEqual(memo?.transcriptConfidence, 1.0)
        XCTAssertEqual(memo?.duration, 3.2)
        XCTAssertEqual(memo?.audioFilename, "memo_\(id.uuidString).m4a")

        let timings = WordTimingsStore(directory: sidecarDir).load(for: id)
        XCTAssertEqual(timings?.count, 4)   // four words
    }

    /// Append a follow-up recording to an existing memo: the new transcript is
    /// appended, the memo becomes user-edited (Mac trusts the combined text), and
    /// the clip is consumed. The placeholder audio can't be merged here, so the base
    /// audio is kept — the real audio merge is device-owed (like all real audio).
    @MainActor
    func testAppendRecordingAppendsTextAndMarksUserEdited() async {
        let repo = NotesRepository(inMemory: true)
        let id = UUID()
        let filename = "memo_\(id.uuidString).m4a"
        try? FileManager.default.createDirectory(at: AppPaths.recordingsDirectory, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: AppPaths.recordingsDirectory.appendingPathComponent(filename).path,
                                       contents: Data("AUDIO".utf8))
        repo.insert(Memo(id: id, audioFilename: filename, duration: 3, recordedAt: Date(),
                         transcript: "first part", transcriptStatus: .done, transcriptConfidence: 0.9))

        let saver = MemoSaver(
            repository: repo,
            transcriber: SeededTranscriber(text: "second part"),
            wordTimings: WordTimingsStore(directory: FileManager.default.temporaryDirectory
                .appendingPathComponent("wt_\(UUID().uuidString)", isDirectory: true)),
            metadataProvider: MockMetadataService()
        )
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent("add_\(UUID().uuidString).m4a")
        FileManager.default.createFile(atPath: temp.path, contents: Data("MORE".utf8))

        await saver.appendRecordingAsync(to: id, tempURL: temp, duration: 2)

        let memo = repo.memo(id: id)
        XCTAssertEqual(memo?.transcript, "first part\n\nsecond part")
        XCTAssertEqual(memo?.transcriptUserEdited, true)
        XCTAssertEqual(memo?.transcriptStatus, .done)
        XCTAssertFalse(FileManager.default.fileExists(atPath: temp.path), "appended clip should be consumed")
        XCTAssertTrue(keptAppendClips(for: id).isEmpty, "consumed clip must not linger in recordings")
    }

    // MARK: - Append robustness (2026-06-10 P0: "append silently adds NO text")

    /// Cold/failed engine: the first transcription attempts throw — the append
    /// must RETRY off the kept clip and land the text, never silently no-op.
    @MainActor
    func testAppendColdEngineRetriesAndLandsText() async {
        let repo = NotesRepository(inMemory: true)
        let id = insertBaseMemo(into: repo)
        let saver = makeAppendSaver(repo: repo,
                                    transcriber: FlakyTranscriber(failures: 2, text: "second part"),
                                    retryDelays: [0, 0, 0])
        let temp = makeTempClip()

        await saver.appendRecordingAsync(to: id, tempURL: temp, duration: 2)

        let memo = repo.memo(id: id)
        XCTAssertEqual(memo?.transcript, "first part\n\nsecond part")
        XCTAssertEqual(memo?.transcriptStatus, .done)
        XCTAssertEqual(memo?.transcriptUserEdited, true)
        XCTAssertTrue(keptAppendClips(for: id).isEmpty, "clip should be consumed once its text landed")
    }

    /// Terminal failure: every attempt throws and there's no live caption. The
    /// memo must SURFACE the failure (`.failed` → the list shows an Error pill),
    /// KEEP the clip on disk as the retry source, and leave the transcript + the
    /// userEdited flag untouched (so the Mac may still re-transcribe the merged audio).
    @MainActor
    func testAppendTerminalFailureSurfacesErrorAndKeepsClip() async {
        let repo = NotesRepository(inMemory: true)
        let id = insertBaseMemo(into: repo)
        let saver = makeAppendSaver(repo: repo,
                                    transcriber: FlakyTranscriber(failures: .max, text: "never"),
                                    retryDelays: [0, 0])
        let temp = makeTempClip()

        await saver.appendRecordingAsync(to: id, tempURL: temp, duration: 2)

        let memo = repo.memo(id: id)
        XCTAssertEqual(memo?.transcript, "first part", "a failed append must not alter the transcript")
        XCTAssertEqual(memo?.transcriptStatus, .failed, "failure must surface, never a silent no-op")
        XCTAssertEqual(memo?.transcriptUserEdited, false, "a failed append must not claim a user edit")
        XCTAssertFalse(FileManager.default.fileExists(atPath: temp.path), "temp clip should be moved, not left behind")
        XCTAssertFalse(keptAppendClips(for: id).isEmpty, "a failed append must KEEP the clip as the retry source")
        cleanupAppendClips(for: id)
    }

    /// The third user repro: append AFTER manually editing the body — the edited
    /// text must be preserved and the new text appended after it.
    @MainActor
    func testAppendAfterManualEditLandsText() async {
        let repo = NotesRepository(inMemory: true)
        let id = insertBaseMemo(into: repo, transcript: "edited by hand", userEdited: true)
        let saver = makeAppendSaver(repo: repo, transcriber: SeededTranscriber(text: "appended bit"))
        let temp = makeTempClip()

        await saver.appendRecordingAsync(to: id, tempURL: temp, duration: 2)

        let memo = repo.memo(id: id)
        XCTAssertEqual(memo?.transcript, "edited by hand\n\nappended bit")
        XCTAssertEqual(memo?.transcriptUserEdited, true)
        XCTAssertEqual(memo?.transcriptStatus, .done)
    }

    /// The 2026-06-21 P0 repro ("paste into a new note → clear it → append → the
    /// whole note vanishes"). A memo whose body was pasted-then-CLEARED
    /// (`transcript == nil`, the editor's `textViewDidChange` on an empty body) must
    /// SURVIVE an append: the appended text becomes the whole body and the memo is
    /// NEVER trashed or deleted. This locks the MemoSaver append path as safe — so a
    /// real-device "note vanished" points at the CloudKit/UI layer, not here.
    @MainActor
    func testAppendAfterClearingBodyKeepsMemoAndLandsText() async {
        let repo = NotesRepository(inMemory: true)
        let id = insertBaseMemo(into: repo, transcript: "pasted text I don't want")
        // Simulate clearing the body in the editor (textViewDidChange → transcript=nil).
        repo.memo(id: id)?.transcript = nil
        repo.save()

        let saver = makeAppendSaver(repo: repo, transcriber: SeededTranscriber(text: "the appended recording"))
        let temp = makeTempClip()
        await saver.appendRecordingAsync(to: id, tempURL: temp, duration: 2)

        let memo = repo.memo(id: id)
        XCTAssertNotNil(memo, "the memo must still exist after appending to a cleared body")
        XCTAssertNil(memo?.deletedAt, "append must NEVER trash the memo")
        XCTAssertEqual(memo?.transcript, "the appended recording", "appended text lands as the whole body")
        XCTAssertEqual(memo?.transcriptStatus, .done)
    }

    /// The engine RAN but heard nothing (silence guard) and there's no caption:
    /// an honest no-text append — prior status restored (not an error), clip consumed.
    @MainActor
    func testAppendSilentClipRestoresPriorStatus() async {
        let repo = NotesRepository(inMemory: true)
        let id = insertBaseMemo(into: repo)
        let saver = makeAppendSaver(repo: repo, transcriber: SeededTranscriber(text: ""))
        let temp = makeTempClip()

        await saver.appendRecordingAsync(to: id, tempURL: temp, duration: 2)

        let memo = repo.memo(id: id)
        XCTAssertEqual(memo?.transcript, "first part")
        XCTAssertEqual(memo?.transcriptStatus, .done, "a silent clip is not an error")
        XCTAssertTrue(keptAppendClips(for: id).isEmpty, "silent clip should be consumed")
    }

    /// Engine silent but the LIVE CAPTION had words → the caption text lands.
    @MainActor
    func testAppendFallsBackToLiveCaptionWhenEngineSilent() async {
        let repo = NotesRepository(inMemory: true)
        let id = insertBaseMemo(into: repo)
        let saver = makeAppendSaver(repo: repo, transcriber: SeededTranscriber(text: ""))
        let temp = makeTempClip()

        await saver.appendRecordingAsync(to: id, tempURL: temp, duration: 2, liveCaption: "caption words")

        let memo = repo.memo(id: id)
        XCTAssertEqual(memo?.transcript, "first part\n\ncaption words")
        XCTAssertEqual(memo?.transcriptStatus, .done)
    }

    // MARK: - Stuck-transcription recovery (2026-06-16 device bug)

    /// A recording orphaned at `.transcribing` by a process kill — a cold-launch
    /// auto-record stopped before the model loaded, then the app was suspended,
    /// so the fire-and-forget transcription Task died — is re-transcribed by the
    /// launch sweep, never left as a permanent spinner.
    @MainActor
    func testRecoverReTranscribesStuckRecording() async {
        let repo = NotesRepository(inMemory: true)
        try? FileManager.default.createDirectory(at: AppPaths.recordingsDirectory, withIntermediateDirectories: true)
        let id = UUID()
        let filename = "memo_\(id.uuidString).m4a"
        FileManager.default.createFile(atPath: AppPaths.recordingsDirectory.appendingPathComponent(filename).path,
                                       contents: Data("AUDIO".utf8))
        repo.insert(Memo(id: id, audioFilename: filename, duration: 13, recordedAt: Date(),
                         transcript: nil, transcriptStatus: .transcribing))

        await makeRecoverySaver(repo: repo, text: "recovered transcript").recoverStuckTranscriptions()

        let memo = repo.memo(id: id)
        XCTAssertEqual(memo?.transcriptStatus, .done)
        XCTAssertEqual(memo?.transcript, "recovered transcript")
        try? FileManager.default.removeItem(at: AppPaths.recordingsDirectory.appendingPathComponent(filename))
    }

    /// The sweep is scoped to PLAIN recordings: capture dictations (empty
    /// `audioFilename` — `CaptureDictation.resumePending` owns those) and
    /// audiobook captures (`isBookCapture`, own transcribe-at-create path) must
    /// be left untouched even when stuck, while a plain stuck memo IS recovered.
    @MainActor
    func testRecoverSkipsCaptureDictationsAndBookCaptures() async {
        let repo = NotesRepository(inMemory: true)
        try? FileManager.default.createDirectory(at: AppPaths.recordingsDirectory, withIntermediateDirectories: true)

        // (a) capture dictation — empty audioFilename, stuck
        let dictationID = UUID()
        repo.insert(Memo(id: dictationID, audioFilename: "", duration: 0, recordedAt: Date(),
                         transcriptStatus: .transcribing))

        // (b) audiobook capture — book metadata + audio present, stuck
        let bookID = UUID()
        let bookFile = "memo_\(bookID.uuidString).m4a"
        FileManager.default.createFile(atPath: AppPaths.recordingsDirectory.appendingPathComponent(bookFile).path,
                                       contents: Data("AUDIO".utf8))
        var bookMeta = MemoMetadata()
        bookMeta.bookTitle = "Meditations"
        repo.insert(Memo.make(id: bookID, audioFilename: bookFile, duration: 5, recordedAt: Date(),
                              transcriptStatus: .transcribing, metadata: bookMeta))

        // (c) plain recording — stuck, SHOULD be recovered
        let plainID = UUID()
        let plainFile = "memo_\(plainID.uuidString).m4a"
        FileManager.default.createFile(atPath: AppPaths.recordingsDirectory.appendingPathComponent(plainFile).path,
                                       contents: Data("AUDIO".utf8))
        repo.insert(Memo(id: plainID, audioFilename: plainFile, duration: 4, recordedAt: Date(),
                         transcriptStatus: .transcribing))

        await makeRecoverySaver(repo: repo, text: "plain recovered").recoverStuckTranscriptions()

        XCTAssertEqual(repo.memo(id: dictationID)?.transcriptStatus, .transcribing, "capture dictation left for CaptureDictation.resumePending")
        XCTAssertEqual(repo.memo(id: bookID)?.transcriptStatus, .transcribing, "audiobook capture left for its own path")
        XCTAssertEqual(repo.memo(id: plainID)?.transcriptStatus, .done, "plain stuck recording recovered")
        XCTAssertEqual(repo.memo(id: plainID)?.transcript, "plain recovered")

        for f in [bookFile, plainFile] {
            try? FileManager.default.removeItem(at: AppPaths.recordingsDirectory.appendingPathComponent(f))
        }
    }

    // MARK: - Stuck-diarization recovery (2026-06-21 device bug)

    /// A "Split speakers" orphaned by app suspension (its fire-and-forget Task died
    /// mid-identify) is left with `pendingDiarizationTarget` set. The launch sweep
    /// re-runs it: the transcript becomes speaker turns and the marker clears.
    @MainActor
    func testRecoverReRunsStuckDiarization() async {
        let repo = NotesRepository(inMemory: true)
        try? FileManager.default.createDirectory(at: AppPaths.recordingsDirectory, withIntermediateDirectories: true)
        let id = UUID()
        let filename = "memo_\(id.uuidString).m4a"
        FileManager.default.createFile(atPath: AppPaths.recordingsDirectory.appendingPathComponent(filename).path,
                                       contents: Data("AUDIO".utf8))
        let memo = Memo(id: id, audioFilename: filename, duration: 28, recordedAt: Date(),
                        transcript: "one two three four", transcriptStatus: .done, transcriptConfidence: 0.9)
        memo.pendingDiarizationTarget = 0   // in-flight, Auto
        repo.insert(memo)

        let sidecar = FileManager.default.temporaryDirectory
            .appendingPathComponent("wt_\(UUID().uuidString)", isDirectory: true)
        let wt = WordTimingsStore(directory: sidecar)
        wt.write((0..<8).map { WordTiming(word: "w\($0)", start: Double($0) * 3, end: Double($0) * 3 + 2.5) }, for: id)

        let saver = MemoSaver(repository: repo, transcriber: SeededTranscriber(text: "x"),
                              diarizer: SeededDiarizer(), wordTimings: wt, metadataProvider: MockMetadataService())
        await saver.recoverStuckDiarizations()

        let result = repo.memo(id: id)
        XCTAssertNil(result?.pendingDiarizationTarget, "the in-flight marker must clear after recovery")
        XCTAssertEqual(result?.transcript?.contains("**"), true, "recovery re-splits into **Speaker:** turns")
        try? FileManager.default.removeItem(at: AppPaths.recordingsDirectory.appendingPathComponent(filename))
    }

    /// Recovery is scoped to in-flight memos: one with no marker is left untouched.
    @MainActor
    func testRecoverSkipsMemosNotMidDiarization() async {
        let repo = NotesRepository(inMemory: true)
        let id = insertBaseMemo(into: repo, transcript: "plain prose")   // pendingDiarizationTarget == nil
        let sidecar = FileManager.default.temporaryDirectory
            .appendingPathComponent("wt_\(UUID().uuidString)", isDirectory: true)
        let wt = WordTimingsStore(directory: sidecar)
        wt.write([WordTiming(word: "a", start: 0, end: 1)], for: id)
        let saver = MemoSaver(repository: repo, transcriber: SeededTranscriber(text: "x"),
                              diarizer: SeededDiarizer(), wordTimings: wt, metadataProvider: MockMetadataService())

        await saver.recoverStuckDiarizations()

        XCTAssertEqual(repo.memo(id: id)?.transcript, "plain prose", "a memo not mid-diarization is untouched")
        XCTAssertNil(repo.memo(id: id)?.pendingDiarizationTarget)
    }

    @MainActor
    private func makeRecoverySaver(repo: NotesRepository, text: String) -> MemoSaver {
        MemoSaver(
            repository: repo,
            transcriber: SeededTranscriber(text: text),
            wordTimings: WordTimingsStore(directory: FileManager.default.temporaryDirectory
                .appendingPathComponent("wt_\(UUID().uuidString)", isDirectory: true)),
            metadataProvider: MockMetadataService())
    }

    // MARK: - Append helpers

    /// Insert a base memo (with placeholder audio on disk) the appends target.
    @MainActor
    private func insertBaseMemo(into repo: NotesRepository,
                                transcript: String? = "first part",
                                userEdited: Bool = false) -> UUID {
        let id = UUID()
        let filename = "memo_\(id.uuidString).m4a"
        FileManager.default.createFile(atPath: AppPaths.recordingsDirectory.appendingPathComponent(filename).path,
                                       contents: Data("AUDIO".utf8))
        repo.insert(Memo(id: id, audioFilename: filename, duration: 3, recordedAt: Date(),
                         transcript: transcript, transcriptStatus: .done,
                         transcriptConfidence: 0.9, transcriptUserEdited: userEdited))
        return id
    }

    @MainActor
    private func makeAppendSaver(repo: NotesRepository,
                                 transcriber: any Transcriber,
                                 retryDelays: [TimeInterval] = [0]) -> MemoSaver {
        MemoSaver(
            repository: repo,
            transcriber: transcriber,
            wordTimings: WordTimingsStore(directory: FileManager.default.temporaryDirectory
                .appendingPathComponent("wt_\(UUID().uuidString)", isDirectory: true)),
            metadataProvider: MockMetadataService(),
            appendRetryDelays: retryDelays
        )
    }

    private func makeTempClip() -> URL {
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent("add_\(UUID().uuidString).m4a")
        FileManager.default.createFile(atPath: temp.path, contents: Data("MORE".utf8))
        return temp
    }

    /// Pending `append_<memoID>_*.m4a` clips kept in the recordings directory.
    private func keptAppendClips(for id: UUID) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: AppPaths.recordingsDirectory.path)) ?? [])
            .filter { $0.hasPrefix("append_\(id.uuidString)") }
    }

    private func cleanupAppendClips(for id: UUID) {
        for name in keptAppendClips(for: id) {
            try? FileManager.default.removeItem(at: AppPaths.recordingsDirectory.appendingPathComponent(name))
        }
    }

    @MainActor
    func testPhotosBuildManifestAndInjectMarkers() async {
        let repo = NotesRepository(inMemory: true)
        let saver = MemoSaver(
            repository: repo,
            transcriber: SeededTranscriber(text: "one two three four five six"),
            wordTimings: WordTimingsStore(directory: FileManager.default.temporaryDirectory
                .appendingPathComponent("wt_\(UUID().uuidString)", isDirectory: true)),
            metadataProvider: MockMetadataService()
        )

        let audio = FileManager.default.temporaryDirectory.appendingPathComponent("rec_\(UUID().uuidString).m4a")
        FileManager.default.createFile(atPath: audio.path, contents: Data())
        let photo = FileManager.default.temporaryDirectory.appendingPathComponent("cap_\(UUID().uuidString).jpg")
        FileManager.default.createFile(atPath: photo.path, contents: Data([0xFF, 0xD8, 0xFF]))

        let id = await saver.saveAndTranscribe(tempURL: audio, duration: 2.0, photos: [(url: photo, offset: 0.35)])

        let memo = repo.memo(id: id)
        XCTAssertEqual(memo?.metadata?.imageManifest?.count, 1)
        XCTAssertEqual(memo?.metadata?.imageManifest?.first?.filename, "photo_\(id.uuidString)_001.jpg")
        XCTAssertEqual(memo?.transcriptMarkersInjected, true)
        XCTAssertTrue(memo?.transcript?.contains("[[img_001]]") ?? false, "marker not injected into transcript")

        let movedPhoto = AppPaths.recordingsDirectory.appendingPathComponent("photo_\(id.uuidString)_001.jpg")
        XCTAssertTrue(FileManager.default.fileExists(atPath: movedPhoto.path))
    }

    @MainActor
    func testImportAudioCopiesFilePreservesExtensionAndCreatesMemo() throws {
        let repo = NotesRepository(inMemory: true)
        let saver = MemoSaver(
            repository: repo,
            transcriber: SeededTranscriber(text: "imported audio"),
            wordTimings: WordTimingsStore(directory: FileManager.default.temporaryDirectory
                .appendingPathComponent("wt_\(UUID().uuidString)", isDirectory: true)),
            metadataProvider: MockMetadataService()
        )

        // An external "shared" audio file — a non-m4a extension to prove the
        // import preserves it (so the Mac sees the right format).
        let source = FileManager.default.temporaryDirectory
            .appendingPathComponent("shared_\(UUID().uuidString).wav")
        FileManager.default.createFile(atPath: source.path, contents: Data([0x52, 0x49, 0x46, 0x46]))

        let id = try XCTUnwrap(saver.importAudio(from: source))

        let memo = repo.memo(id: id)
        XCTAssertEqual(memo?.audioFilename, "memo_\(id.uuidString).wav")  // extension preserved
        XCTAssertEqual(memo?.syncStatus, .waiting)
        let copied = AppPaths.recordingsDirectory.appendingPathComponent("memo_\(id.uuidString).wav")
        XCTAssertTrue(FileManager.default.fileExists(atPath: copied.path), "imported audio not copied into recordings")
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path), "import must copy, not move the source")
    }

    @MainActor
    func testMetadataCaptureMergesAndPreservesManifest() async {
        let repo = NotesRepository(inMemory: true)
        let captured = MemoMetadata(
            capturedAt: "2026-06-06T10:00:00.000Z",
            location: LocationInfo(latitude: 38.7, longitude: -9.1, placeName: "Lisbon"),
            dayPeriod: .morning,
            steps: 500,
            tags: []
        )
        let saver = MemoSaver(
            repository: repo,
            transcriber: SeededTranscriber(text: "one two three four five six"),
            wordTimings: WordTimingsStore(directory: FileManager.default.temporaryDirectory
                .appendingPathComponent("wt_\(UUID().uuidString)", isDirectory: true)),
            metadataProvider: MockMetadataService(captured)
        )

        let audio = FileManager.default.temporaryDirectory.appendingPathComponent("rec_\(UUID().uuidString).m4a")
        FileManager.default.createFile(atPath: audio.path, contents: Data())
        let photo = FileManager.default.temporaryDirectory.appendingPathComponent("cap_\(UUID().uuidString).jpg")
        FileManager.default.createFile(atPath: photo.path, contents: Data([0xFF, 0xD8, 0xFF]))

        let id = await saver.saveAndTranscribe(tempURL: audio, duration: 2.0, photos: [(url: photo, offset: 0.35)])

        let memo = repo.memo(id: id)
        XCTAssertEqual(memo?.metadata?.location?.placeName, "Lisbon")   // captured context merged in
        XCTAssertEqual(memo?.metadata?.steps, 500)
        XCTAssertEqual(memo?.metadata?.dayPeriod, .morning)
        XCTAssertEqual(memo?.metadata?.imageManifest?.count, 1)         // photo manifest preserved
        XCTAssertTrue(memo?.transcript?.contains("[[img_001]]") ?? false)
    }
}

/// Transcriber stub that throws for the first `failures` calls, then returns
/// `text` — the cold/failed-engine shape the append retry loop must survive.
private actor FlakyTranscriber: Transcriber {
    struct NotReady: Error {}

    private var failuresLeft: Int
    private let text: String

    init(failures: Int, text: String) {
        self.failuresLeft = failures
        self.text = text
    }

    func transcribe(audioURL: URL, imageManifest: [ImageManifestEntry]) async throws -> TranscriptionResult {
        if failuresLeft > 0 {
            failuresLeft -= 1
            throw NotReady()
        }
        let timings = text.split(separator: " ").enumerated().map { index, word in
            WordTiming(word: String(word), start: Double(index) * 0.3, end: Double(index) * 0.3 + 0.25)
        }
        return TranscriptionResult(text: text, confidence: 1.0, durationMs: 0,
                                   wordTimings: timings, markersInjected: false)
    }
}
