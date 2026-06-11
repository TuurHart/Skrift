import XCTest
@testable import SkriftMobile

/// Settings → Capture → "Copy transcript to clipboard" (opt-in, DEFAULT OFF) +
/// the in-record camera flip (front/back).
///
/// The clipboard write is injected so the host's real pasteboard is never
/// touched, and the opt-in is read from a throwaway UserDefaults suite.
final class AutoCopyAndCameraFlipTests: XCTestCase {

    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "autocopy_test_\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    /// Collects what the saver "copied to the clipboard".
    private final class Clipboard {
        var copies: [String] = []
    }

    @MainActor
    private func makeSaver(repo: NotesRepository, text: String, clipboard: Clipboard) -> MemoSaver {
        MemoSaver(
            repository: repo,
            transcriber: SeededTranscriber(text: text),
            wordTimings: WordTimingsStore(directory: FileManager.default.temporaryDirectory
                .appendingPathComponent("wt_\(UUID().uuidString)", isDirectory: true)),
            metadataProvider: MockMetadataService(),
            defaults: defaults,
            copyToClipboard: { [weak clipboard] in clipboard?.copies.append($0) }
        )
    }

    private func makeTempAudio() -> URL {
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("rec_\(UUID().uuidString).m4a")
        FileManager.default.createFile(atPath: temp.path, contents: Data())
        return temp
    }

    // MARK: - Auto-copy after transcription

    /// User-locked: the setting is opt-in and DEFAULT OFF — a fresh install must
    /// never touch the clipboard.
    @MainActor
    func testAutoCopyOffByDefault() async {
        let repo = NotesRepository(inMemory: true)
        let clipboard = Clipboard()
        let saver = makeSaver(repo: repo, text: "hello world", clipboard: clipboard)

        let id = await saver.saveAndTranscribe(tempURL: makeTempAudio(), duration: 1.0)

        XCTAssertEqual(repo.memo(id: id)?.transcriptStatus, .done)
        XCTAssertTrue(clipboard.copies.isEmpty, "default OFF must never write the clipboard")
    }

    /// Opted in: a completed transcription copies the FINAL transcript.
    @MainActor
    func testAutoCopyOnCopiesFinalTranscript() async {
        defaults.set(true, forKey: MemoSaver.autoCopySettingKey)
        let repo = NotesRepository(inMemory: true)
        let clipboard = Clipboard()
        let saver = makeSaver(repo: repo, text: "hello world from skrift", clipboard: clipboard)

        let id = await saver.saveAndTranscribe(tempURL: makeTempAudio(), duration: 1.0)

        XCTAssertEqual(repo.memo(id: id)?.transcript, "hello world from skrift")
        XCTAssertEqual(clipboard.copies, ["hello world from skrift"])
    }

    /// Opted in but the engine heard nothing: the memo fails — the clipboard
    /// must NOT be overwritten with emptiness.
    @MainActor
    func testAutoCopySkipsEmptyTranscript() async {
        defaults.set(true, forKey: MemoSaver.autoCopySettingKey)
        let repo = NotesRepository(inMemory: true)
        let clipboard = Clipboard()
        let saver = makeSaver(repo: repo, text: "", clipboard: clipboard)

        let id = await saver.saveAndTranscribe(tempURL: makeTempAudio(), duration: 1.0)

        XCTAssertEqual(repo.memo(id: id)?.transcriptStatus, .failed)
        XCTAssertTrue(clipboard.copies.isEmpty, "an empty transcript must not be copied")
    }

    /// Opted in: an APPEND copies the combined transcript (the whole memo, not
    /// just the new clip) once the appended text lands.
    @MainActor
    func testAutoCopyOnAppendCopiesCombinedTranscript() async {
        defaults.set(true, forKey: MemoSaver.autoCopySettingKey)
        let repo = NotesRepository(inMemory: true)
        let clipboard = Clipboard()
        let saver = makeSaver(repo: repo, text: "second part", clipboard: clipboard)

        let id = UUID()
        let filename = "memo_\(id.uuidString).m4a"
        try? FileManager.default.createDirectory(at: AppPaths.recordingsDirectory, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: AppPaths.recordingsDirectory.appendingPathComponent(filename).path,
                                       contents: Data("AUDIO".utf8))
        repo.insert(Memo(id: id, audioFilename: filename, duration: 3, recordedAt: Date(),
                         transcript: "first part", transcriptStatus: .done, transcriptConfidence: 0.9))

        let temp = FileManager.default.temporaryDirectory.appendingPathComponent("add_\(UUID().uuidString).m4a")
        FileManager.default.createFile(atPath: temp.path, contents: Data("MORE".utf8))

        await saver.appendRecordingAsync(to: id, tempURL: temp, duration: 2)

        XCTAssertEqual(clipboard.copies, ["first part\n\nsecond part"],
                       "append must copy the COMBINED transcript")
    }

    // MARK: - Camera flip (mock mode — the Simulator has no camera)

    /// The flip toggles the published position back→front→back; the photo
    /// pipeline (capture → offset → manifest) is untouched by a flip.
    @MainActor
    func testFlipCameraTogglesPositionInMockMode() {
        let camera = PhotoCaptureService(mock: true)
        camera.configure()
        XCTAssertEqual(camera.position, .back)

        camera.flipCamera()
        XCTAssertEqual(camera.position, .front)

        camera.capture(offsetSeconds: 1.5)
        XCTAssertEqual(camera.capturedCount, 1, "capturing must keep working after a flip")

        camera.flipCamera()
        XCTAssertEqual(camera.position, .back)

        camera.discardAll()
    }
}
