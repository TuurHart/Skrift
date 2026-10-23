import XCTest
@testable import SkriftMobile

/// Q480 (C151, D46): a transcript records the ASR language mode it was made with, and ⋯ offers
/// "Transcribe again in Dutch / English" (the other mode) on that note only. The global setting
/// stays the default. Fixture: corpus `voice-nl-recorded-in-english-mode`.
final class TranscribeAgainLanguageTests: XCTestCase {

    /// Answers in the mode it is asked for, and remembers what it was asked.
    final class ModeTranscriber: Transcribing, @unchecked Sendable {
        let english: String, dutch: String
        var fail = false
        private(set) var asked: [ASRLanguageMode] = []
        init(english: String, dutch: String) { self.english = english; self.dutch = dutch }

        /// The plain pass does not say which mode it ran in (like an old engine).
        func transcribe(audioURL: URL, imageManifest: [ImageManifestEntry]) async throws -> TranscriptionResult {
            var result = try await transcribe(audioURL: audioURL, imageManifest: imageManifest, mode: .english)
            asked.removeLast()
            result.languageMode = nil
            return result
        }

        func transcribe(audioURL: URL, imageManifest: [ImageManifestEntry],
                        mode: ASRLanguageMode) async throws -> TranscriptionResult {
            asked.append(mode)
            struct Down: Error {}
            if fail { throw Down() }
            let text = mode.isMultilingual ? dutch : english
            let words = text.split(separator: " ").enumerated().map {
                WordTiming(word: String($0.element), start: Double($0.offset) * 0.3, end: Double($0.offset) * 0.3 + 0.25)
            }
            return TranscriptionResult(text: text, confidence: 0.9, durationMs: 0, wordTimings: words,
                                       markersInjected: false, languageMode: mode)
        }
    }

    private struct Expect: Decodable {
        let offeredBefore: String, offeredAfter: String, multilingualTranscript: String
    }
    private struct Wrapper: Decodable { let expect: Expect }

    private var savedSetting: Any?
    private var copiedAudio: URL?

    override func setUp() {
        savedSetting = UserDefaults.standard.object(forKey: ASRLanguageMode.settingKey)
        UserDefaults.standard.set(false, forKey: ASRLanguageMode.settingKey)   // global = English
    }

    override func tearDown() {
        if let savedSetting { UserDefaults.standard.set(savedSetting, forKey: ASRLanguageMode.settingKey) }
        else { UserDefaults.standard.removeObject(forKey: ASRLanguageMode.settingKey) }
        if let copiedAudio { try? FileManager.default.removeItem(at: copiedAudio) }
    }

    @MainActor
    private func seeded() throws -> (NotesRepository, Memo, Expect) {
        let dir = CorpusSeed.fixtureRoot(file: #filePath).appendingPathComponent("notes/voice-nl-recorded-in-english-mode")
        let data = try Data(contentsOf: dir.appendingPathComponent("note.json"))
        let note = try JSONDecoder().decode(CorpusSeed.Note.self, from: data)
        let expect = try JSONDecoder().decode(Wrapper.self, from: data).expect
        let id = try XCTUnwrap(UUID(uuidString: note.id))
        let repo = NotesRepository(inMemory: true)
        let memo = CorpusSeed.makeMemo(note, id: id)
        repo.context.insert(memo)
        try repo.context.save()
        let audio = try XCTUnwrap(memo.audioURL)
        try FileManager.default.createDirectory(at: audio.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: audio)
        try FileManager.default.copyItem(at: dir.appendingPathComponent("audio.m4a"), to: audio)
        copiedAudio = audio
        return (repo, memo, expect)
    }

    @MainActor
    private func saver(_ repo: NotesRepository, _ transcriber: any Transcribing) -> MemoSaver {
        MemoSaver(repository: repo, transcriber: transcriber,
                  wordTimings: WordTimingsStore(directory: FileManager.default.temporaryDirectory
                    .appendingPathComponent("wt_\(UUID().uuidString)", isDirectory: true)),
                  metadataProvider: MockMetadataService())
    }

    // MARK: - the label rule

    func testLabelNamesTheOtherLanguage() {
        XCTAssertEqual(ASRLanguageMode.transcribeAgainLabel(recordedIn: .english), "Transcribe again in Dutch")
        XCTAssertEqual(ASRLanguageMode.transcribeAgainLabel(recordedIn: .multilingual), "Transcribe again in English")
        XCTAssertEqual(ASRLanguageMode.recorded("multilingual", default: .english), .multilingual)
        XCTAssertEqual(ASRLanguageMode.recorded(nil, default: .multilingual), .multilingual, "unstamped = the setting")
        XCTAssertEqual(ASRLanguageMode.recorded("klingon", default: .english), .english)
    }

    // MARK: - the corpus note

    @MainActor
    func testDutchNoteRecordedInEnglishModeTranscribesAgainInDutch() async throws {
        let (repo, memo, expect) = try seeded()
        let englishBody = memo.transcript
        XCTAssertEqual(memo.transcriptLanguageMode, "english", "the fixture carries its stamp")
        XCTAssertTrue(MemoSaver.canTranscribeAgain(memo))
        XCTAssertEqual(ASRLanguageMode.transcribeAgainLabel(recordedIn: MemoSaver.recordedMode(memo)), expect.offeredBefore)

        let engine = ModeTranscriber(english: englishBody ?? "", dutch: expect.multilingualTranscript)
        let landed = await saver(repo, engine).transcribeAgain(id: memo.id, in: MemoSaver.recordedMode(memo).other)
        XCTAssertTrue(landed)
        XCTAssertEqual(engine.asked, [.multilingual], "one pass, in the OTHER mode")

        let after = try XCTUnwrap(repo.memo(id: memo.id))
        XCTAssertEqual(after.transcript, expect.multilingualTranscript)
        XCTAssertEqual(after.transcriptLanguageMode, ASRLanguageMode.multilingual.rawValue)
        XCTAssertEqual(after.transcriptStatus, .done)
        XCTAssertFalse(after.transcriptUserEdited, "the Mac still re-links the fresh words")
        XCTAssertNotNil(after.editedAt, "marked edited, so the Mac adopts and polishes the new words")
        XCTAssertEqual(ASRLanguageMode.transcribeAgainLabel(recordedIn: MemoSaver.recordedMode(after)), expect.offeredAfter)
        XCTAssertFalse(ASRLanguageStore.isMultilingual(), "the global setting stays the default")
    }

    @MainActor
    func testAFailedPassLeavesTheNoteAsItWas() async throws {
        let (repo, memo, expect) = try seeded()
        let before = (memo.transcript, memo.transcriptLanguageMode, memo.transcriptConfidence, memo.editedAt)
        let engine = ModeTranscriber(english: "", dutch: expect.multilingualTranscript)
        engine.fail = true
        let landed = await saver(repo, engine).transcribeAgain(id: memo.id, in: .multilingual)
        XCTAssertFalse(landed)
        let after = try XCTUnwrap(repo.memo(id: memo.id))
        XCTAssertEqual(after.transcript, before.0)
        XCTAssertEqual(after.transcriptLanguageMode, before.1)
        XCTAssertEqual(after.transcriptConfidence, before.2)
        XCTAssertEqual(after.editedAt, before.3)

        // A pass that hears nothing is a failure too, never an emptied note.
        let silent = ModeTranscriber(english: "", dutch: "")
        let emptied = await saver(repo, silent).transcribeAgain(id: memo.id, in: .multilingual)
        XCTAssertFalse(emptied)
        XCTAssertEqual(repo.memo(id: memo.id)?.transcript, before.0)
    }

    @MainActor
    func testNotOfferedWhereANewPassWouldDestroySomething() throws {
        let (repo, memo, _) = try seeded()
        defer { withExtendedLifetime(repo) {} }   // a SwiftData model traps once its context is gone
        memo.transcriptUserEdited = true
        XCTAssertFalse(MemoSaver.canTranscribeAgain(memo), "would run over the user's words")
        memo.transcriptUserEdited = false
        memo.transcript = "**Speaker 1:** Hallo daar.\n\n**Speaker 2:** Goedemorgen."
        XCTAssertFalse(MemoSaver.canTranscribeAgain(memo), "the turns are the only copy of the diarization")
        memo.transcript = "Vandaag."
        memo.transcriptStatus = .transcribing
        XCTAssertFalse(MemoSaver.canTranscribeAgain(memo), "nothing to redo yet")
        memo.transcriptStatus = .done
        memo.audioFilename = ""
        XCTAssertFalse(MemoSaver.canTranscribeAgain(memo), "no audio")
    }

    // MARK: - every transcription stamps its mode

    @MainActor
    func testARecordingsTranscriptRecordsTheModeItWasMadeIn() async {
        let repo = NotesRepository(inMemory: true)
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent("rec_\(UUID().uuidString).m4a")
        FileManager.default.createFile(atPath: temp.path, contents: Data())
        // A plain stub (no mode of its own) is stamped with the setting.
        let id = await saver(repo, SeededTranscriber(text: "hello world")).saveAndTranscribe(tempURL: temp, duration: 1)
        XCTAssertEqual(repo.memo(id: id)?.transcriptLanguageMode, ASRLanguageMode.english.rawValue)
        if let url = repo.memo(id: id)?.audioURL { try? FileManager.default.removeItem(at: url) }

        // The setting moved to Multilingual: the next note says so.
        UserDefaults.standard.set(true, forKey: ASRLanguageMode.settingKey)
        let temp2 = FileManager.default.temporaryDirectory.appendingPathComponent("rec_\(UUID().uuidString).m4a")
        FileManager.default.createFile(atPath: temp2.path, contents: Data())
        let engine = ModeTranscriber(english: "hello", dutch: "hallo")
        let id2 = await saver(repo, engine).saveAndTranscribe(tempURL: temp2, duration: 1)
        XCTAssertEqual(repo.memo(id: id2)?.transcriptLanguageMode, ASRLanguageMode.multilingual.rawValue)
        XCTAssertTrue(engine.asked.isEmpty, "a recording takes the plain pass: the setting decides")
        if let url = repo.memo(id: id2)?.audioURL { try? FileManager.default.removeItem(at: url) }
    }
}
