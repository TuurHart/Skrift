import AVFoundation
import XCTest
@testable import SkriftMobile

/// Q150 / C79 / C145: audio of an hour or more is offered Audiobook vs Voice note at Open-in /
/// AirDrop and the Files importer, not only in the share sheet. One shared `LongAudioRoute`
/// carries the threshold and the words; the answer is carried out by `AppURLHandler.resolve`.
final class LongAudioOfferTests: XCTestCase {

    private var dir: URL!
    private var savedProbe: ((URL) -> TimeInterval?)!

    @MainActor
    override func setUp() {
        super.setUp()
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("LongAudioOffer_\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        savedProbe = AppURLHandler.durationProbe
        AudioPickBridge.shared.pending = nil
    }

    @MainActor
    override func tearDown() {
        AppURLHandler.durationProbe = savedProbe
        AudioPickBridge.shared.pending = nil
        try? FileManager.default.removeItem(at: dir)
        super.tearDown()
    }

    private func clip(_ name: String, seconds: Double = 0.5) throws -> URL {
        let url = dir.appendingPathComponent(name)
        let format = AVAudioFormat(standardFormatWithSampleRate: 16000, channels: 1)!
        let frames = AVAudioFrameCount(16000 * seconds)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        try file.write(from: buffer)
        return url
    }

    // MARK: - The shared choice type

    func testThresholdIsOneHourAndAudiobookIsTheDefault() {
        XCTAssertEqual(LongAudioRoute.threshold, 3600)
        XCTAssertEqual(LongAudioRoute.default, .audiobook)
        XCTAssertFalse(LongAudioRoute.isLong(3599.9))
        XCTAssertTrue(LongAudioRoute.isLong(3600))
        XCTAssertFalse(LongAudioRoute.isLong(nil), "an unreadable length is a voice note")
        XCTAssertTrue(LongAudioRoute.needsOffer(durations: [12, nil, 7200]))
        XCTAssertFalse(LongAudioRoute.needsOffer(durations: [12, nil]))
    }

    func testWordingIsTheShareSheetsWording() {
        XCTAssertEqual(LongAudioRoute.audiobook.title, "Audiobook")
        XCTAssertEqual(LongAudioRoute.audiobook.subtitle, "Read-along in the Books tab — it's a long one")
        XCTAssertEqual(LongAudioRoute.voiceNote.title, "Voice note")
        XCTAssertEqual(LongAudioRoute.voiceNote.subtitle, "Transcribe the whole thing as a note")
    }

    // MARK: - The offer is made at the Open-in / Files door

    /// One two-hour clip (Open-in, AirDrop or a Files pick) raises the question; nothing imports yet.
    @MainActor
    func testASingleLongClipRaisesTheOffer() throws {
        let long = try clip("lecture.caf")
        AppURLHandler.durationProbe = { _ in 7200 }
        let before = NotesRepository.shared.allMemos().count
        AppURLHandler.handle(batch: [long])
        XCTAssertEqual(AudioPickBridge.shared.pending?.hasLongClip, true)
        XCTAssertEqual(AudioPickBridge.shared.pending?.clipCount, 1)
        XCTAssertEqual(NotesRepository.shared.allMemos().count, before, "nothing lands until the user answers")
    }

    /// A short clip alone is no question, as ever.
    @MainActor
    func testAShortClipAloneIsNotOffered() throws {
        let short = try clip("quick.caf")
        AppURLHandler.durationProbe = { _ in 30 }
        // The file is a real clip; only the import would run, which this test does not want.
        XCTAssertFalse(LongAudioRoute.needsOffer(durations: [AppURLHandler.durationProbe(short)]))
    }

    /// Several clips, one of them long: both questions are open.
    @MainActor
    func testLongClipAmongSeveralMarksThePick() throws {
        let urls = [try clip("a.caf"), try clip("b.caf"), try clip("c.caf")]
        AppURLHandler.durationProbe = { $0.lastPathComponent == "b.caf" ? 5400 : 20 }
        AppURLHandler.handle(batch: urls)
        XCTAssertEqual(AudioPickBridge.shared.pending?.hasLongClip, true)
        XCTAssertEqual(AudioPickBridge.shared.pending?.clipCount, 3)
    }

    /// Without a long clip the old rule holds: 2+ clips ask One note / N notes, flagged short.
    @MainActor
    func testSeveralShortClipsKeepTheOldQuestion() throws {
        let urls = [try clip("a.caf"), try clip("b.caf")]
        AppURLHandler.durationProbe = { _ in 20 }
        AppURLHandler.handle(batch: urls)
        XCTAssertEqual(AudioPickBridge.shared.pending?.hasLongClip, false)
        XCTAssertEqual(AudioPickBridge.shared.pending?.clipCount, 2)
    }

    /// The default probe reads a real file's length from its header.
    @MainActor
    func testTheRealProbeReadsALength() throws {
        let url = try clip("half.caf", seconds: 0.5)
        XCTAssertEqual(savedProbe(url) ?? 0, 0.5, accuracy: 0.05)
        XCTAssertNil(savedProbe(dir.appendingPathComponent("missing.caf")))
    }

    // MARK: - The answer is carried out

    /// Audiobook: the clip becomes a book in the library and no note is made.
    @MainActor
    func testAudiobookAnswerAddsABookAndNoMemo() async throws {
        let url = try clip("lecture.caf", seconds: 1)
        let library = AudiobookLibraryStore(directory: dir.appendingPathComponent("library", isDirectory: true))
        let repo = NotesRepository(inMemory: true)
        let saver = MemoSaver(repository: repo, transcriber: SeededTranscriber(text: "x"),
                              wordTimings: WordTimingsStore(directory: dir.appendingPathComponent("wt", isDirectory: true)),
                              metadataProvider: MockMetadataService())
        let jump = await AppURLHandler.resolve([url], choice: .oneNote, route: .audiobook,
                                               saver: saver, library: library)
        XCTAssertNil(jump, "a book, not a note: nothing to open")
        XCTAssertEqual(library.books.count, 1)
        XCTAssertEqual(repo.allMemos().count, 0)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path), "the user's file is untouched")
    }

    /// Voice note: the same long clip goes the note way (`route` defaults to voice note).
    @MainActor
    func testVoiceNoteAnswerMakesAMemoAndNoBook() async throws {
        let url = try clip("lecture.caf", seconds: 1)
        let library = AudiobookLibraryStore(directory: dir.appendingPathComponent("library", isDirectory: true))
        let repo = NotesRepository(inMemory: true)
        let saver = MemoSaver(repository: repo, transcriber: SeededTranscriber(text: "x"),
                              wordTimings: WordTimingsStore(directory: dir.appendingPathComponent("wt", isDirectory: true)),
                              metadataProvider: MockMetadataService())
        let id = await AppURLHandler.resolve([url], choice: .separateNotes, route: .voiceNote,
                                             saver: saver, library: library)
        XCTAssertNotNil(id)
        XCTAssertEqual(repo.allMemos().count, 1)
        XCTAssertTrue(library.books.isEmpty)
        for m in repo.allMemos() { if let f = m.audioURL { try? FileManager.default.removeItem(at: f) } }
    }
}
