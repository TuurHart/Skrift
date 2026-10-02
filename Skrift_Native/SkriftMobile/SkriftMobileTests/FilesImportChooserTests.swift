import AVFoundation
import XCTest
@testable import SkriftMobile

/// Q132 / C68 / C145 / C238: three voice notes picked in Files (or AirDropped / Opened-in as a
/// burst) meet the One note / N notes chooser instead of silently becoming three notes, and
/// the answer is carried out through the shared `AudioClipMerge`.
final class FilesImportChooserTests: XCTestCase {

    private var dir: URL!
    private var made: [URL] = []

    override func setUp() {
        super.setUp()
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("FilesImportChooser_\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: dir)
        for u in made { try? FileManager.default.removeItem(at: u) }
        made = []
        super.tearDown()
    }

    @MainActor
    private func saver(_ repo: NotesRepository) -> MemoSaver {
        MemoSaver(repository: repo, transcriber: SeededTranscriber(text: "merged story"),
                  wordTimings: WordTimingsStore(directory: dir.appendingPathComponent("wt", isDirectory: true)),
                  metadataProvider: MockMetadataService())
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

    private func three() throws -> [URL] {
        try ["a.caf", "b.caf", "c.caf"].map { try clip($0) }
    }

    // MARK: - The question is asked

    /// Only voice notes count: a book bundle, a video and a picture are not part of the question.
    func testOnlyVoiceNotesCountTowardsTheChooser() {
        let urls = ["a.m4a", "b.wav", "movie.mov", "photo.jpg", "book.skriftbook", "notes.md"]
            .map { URL(fileURLWithPath: "/tmp/\($0)") }
        XCTAssertEqual(AppURLHandler.audioClips(in: urls).map(\.lastPathComponent), ["a.m4a", "b.wav"])
    }

    /// Three m4a in one Files pick raise the chooser and import NOTHING yet.
    @MainActor
    func testThreeAudioFilesRaiseTheChooserAndImportNothing() throws {
        AudioPickBridge.shared.pending = nil
        let before = NotesRepository.shared.allMemos().count
        let urls = try three()
        AppURLHandler.handle(batch: urls)
        XCTAssertEqual(AudioPickBridge.shared.pending?.clipCount, 3)
        XCTAssertEqual(AudioPickBridge.shared.pending?.urls, urls)
        XCTAssertEqual(NotesRepository.shared.allMemos().count, before, "nothing lands until the user answers")
        AudioPickBridge.shared.pending = nil
    }

    /// One voice note (with or without a picture beside it) is not a question.
    @MainActor
    func testASingleVoiceNoteSkipsTheChooser() {
        AudioPickBridge.shared.pending = nil
        AppURLHandler.handle(batch: [URL(fileURLWithPath: "/tmp/not-there-\(UUID()).m4a"),
                                     URL(fileURLWithPath: "/tmp/not-there-\(UUID()).jpg")])
        XCTAssertNil(AudioPickBridge.shared.pending)
    }

    /// The chooser reads the ONE shared wording (the share sheet reads the same enum).
    func testChooserWordingIsTheSharedOne() {
        XCTAssertTrue(AudioImportChoice.needsChoice(clipCount: 2))
        XCTAssertFalse(AudioImportChoice.needsChoice(clipCount: 1))
        XCTAssertEqual(AudioImportChoice.default, .oneNote)
        XCTAssertEqual(AudioImportChoice.oneNote.title(clipCount: 3), "One note")
        XCTAssertEqual(AudioImportChoice.separateNotes.title(clipCount: 3), "3 notes")
        XCTAssertEqual(AudioImportChoice.oneNote.confirmTitle(clipCount: 3), "Save as one note")
        XCTAssertEqual(AudioImportChoice.separateNotes.confirmTitle(clipCount: 3), "Save 3 notes")
    }

    // MARK: - The answer is carried out

    /// 'One note': ONE memo for three clips, the user's files untouched.
    @MainActor
    func testOneNoteMergesThreeClipsIntoOneMemo() async throws {
        let repo = NotesRepository(inMemory: true)
        let urls = try three()
        let id = await AppURLHandler.resolve(urls, choice: .oneNote, saver: saver(repo))
        let memos = repo.allMemos()
        XCTAssertEqual(memos.count, 1, "three clips, one note")
        XCTAssertEqual(memos.first?.id, id)
        XCTAssertEqual(MemoOpenBridge.shared.consume(), id, "jumps to the new note")
        for u in urls { XCTAssertTrue(FileManager.default.fileExists(atPath: u.path), "\(u.lastPathComponent) is the user's file") }
        // The merge runs behind the placeholder; wait for the single transcription pass.
        for _ in 0..<100 where repo.memo(id: id!)?.transcriptStatus != .done {
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTAssertEqual(repo.memo(id: id!)?.transcriptStatus, .done)
        XCTAssertEqual(repo.memo(id: id!)?.duration ?? 0, 1.5, accuracy: 0.4, "durations summed")
        for m in memos { if let f = m.audioURL { made.append(f) } }
    }

    /// 'N notes': one memo per clip.
    @MainActor
    func testNNotesMakesOneMemoPerClip() async throws {
        let repo = NotesRepository(inMemory: true)
        let urls = try three()
        await AppURLHandler.resolve(urls, choice: .separateNotes, saver: saver(repo))
        let memos = repo.allMemos()
        XCTAssertEqual(memos.count, 3)
        for u in urls { XCTAssertTrue(FileManager.default.fileExists(atPath: u.path)) }
        for m in memos { if let f = m.audioURL { made.append(f) } }
    }

    /// The merge order is the ONE bundle order (`FilenameDate.chronologicalOrder`): clips named
    /// by date are stitched oldest first whatever order they were picked in.
    func testMergeOrderIsChronologicalByFilenameDate() throws {
        let late = try clip("signal-2026-10-03-09-00-00.caf")
        let early = try clip("signal-2026-10-01-09-00-00.caf")
        let mid = try clip("signal-2026-10-02-09-00-00.caf")
        let staged = AppURLHandler.stageForMerge([late, early, mid])
        defer { for u in staged.urls { try? FileManager.default.removeItem(at: u) } }
        XCTAssertEqual(staged.urls.count, 3)
        XCTAssertEqual(staged.dates.compactMap { $0 }, staged.dates.compactMap { $0 }.sorted())
        XCTAssertTrue(staged.urls[0].lastPathComponent.contains("_1."), "the oldest (picked second) goes first")
        XCTAssertTrue(staged.urls[2].lastPathComponent.contains("_0."), "the newest (picked first) goes last")
        // Staging copies: the originals are still there.
        for u in [late, early, mid] { XCTAssertTrue(FileManager.default.fileExists(atPath: u.path)) }
    }

    /// Picked with no dates to go by, the arrival order stands.
    func testUndatedPickKeepsArrivalOrder() throws {
        let urls = try three()
        // All three were just written: their file dates sit within `sameMoment` of each other.
        let staged = AppURLHandler.stageForMerge(urls)
        defer { for u in staged.urls { try? FileManager.default.removeItem(at: u) } }
        XCTAssertEqual(staged.urls.map { $0.lastPathComponent.split(separator: "_").last! }.map { String($0.prefix(1)) },
                       ["0", "1", "2"])
    }
}
