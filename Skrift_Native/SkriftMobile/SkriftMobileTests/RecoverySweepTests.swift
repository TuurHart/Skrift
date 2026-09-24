import AVFoundation
import OSLog
import XCTest
@testable import SkriftMobile

/// C99 / C287 / C288 / C263 / D131 / R46 — a recording is never lost.
/// Drives the real segment writer (`RecordingCheckpoint`, real AAC files) and
/// the real launch sweep (`MemoSaver.recoverInterruptedRecordings`) against a
/// temp directory; a "kill" is a segment/main file left open (no MP4 index).
@MainActor
final class RecoverySweepTests: XCTestCase {
    private var dir: URL!
    private var createdMemoFiles: [URL] = []
    private let rate: Double = 44_100

    override func setUp() async throws {
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("sweep_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: dir)
        for url in createdMemoFiles { try? FileManager.default.removeItem(at: url) }
    }

    // MARK: helpers

    private var settings: [String: Any] {
        [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: rate,
         AVNumberOfChannelsKey: 1, AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue]
    }

    private func tone(seconds: Double) -> AVAudioPCMBuffer {
        let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1)!
        let frames = AVAudioFrameCount(rate * seconds)
        let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buf.frameLength = frames
        let ch = buf.floatChannelData![0]
        for i in 0..<Int(frames) { ch[i] = 0.3 * sinf(Float(i) * 2 * .pi * 440 / Float(rate)) }
        return buf
    }

    /// A take as a previous process run left it: re-stamp its marker with a
    /// foreign session id (this run's takes are live and never swept).
    private func pretendPreviousRun(_ cp: RecordingCheckpoint, finalized: Bool? = nil) throws {
        var m = try JSONDecoder().decode(RecordingMarker.self, from: Data(contentsOf: cp.markerURL))
        m.sessionID = "previous-run"
        if let finalized { m.finalized = finalized }
        try JSONEncoder().encode(m).write(to: cp.markerURL)
    }

    private func saver(_ repo: NotesRepository, text: String = "engine words") -> MemoSaver {
        MemoSaver(repository: repo, transcriber: SeededTranscriber(text: text),
                  wordTimings: WordTimingsStore(directory: dir), metadataProvider: MockMetadataService())
    }

    private func track(_ repo: NotesRepository, _ ids: [UUID]) {
        for id in ids {
            if let m = repo.memo(id: id) {
                createdMemoFiles.append(AppPaths.recordingsDirectory.appendingPathComponent(m.audioFilename))
            }
        }
    }

    private func duration(_ url: URL) throws -> Double {
        let f = try AVAudioFile(forReading: url)
        return Double(f.length) / f.fileFormat.sampleRate
    }

    // MARK: C99 — segments during the take

    func testSegmentIntervalIsSixtySeconds() {
        XCTAssertEqual(RecordingCheckpoint.segmentSeconds, 60)
    }

    func testSegmentsCloseOnIntervalAndOnInterruptionAndMarkerListsThem() throws {
        let cp = RecordingCheckpoint(directory: dir, takeID: "T1", settings: settings,
                                     sampleRate: rate, segmentSeconds: 0.5)
        XCTAssertTrue(FileManager.default.fileExists(atPath: cp.markerURL.path),
                      "the marker exists from the take's first instant")
        try cp.write(tone(seconds: 0.6))          // crosses 0.5 s → closed by the interval
        try cp.write(tone(seconds: 0.2))
        cp.rotate(reason: "interrupt")             // a call arrives → closed now
        let m = try JSONDecoder().decode(RecordingMarker.self, from: Data(contentsOf: cp.markerURL))
        XCTAssertEqual(m.segments, ["rec_seg_T1_001.m4a", "rec_seg_T1_002.m4a"])
        XCTAssertFalse(m.finalized)
        for url in cp.segmentURLs {
            XCTAssertTrue(RecordingCheckpoint.isReadableAudio(url), "\(url.lastPathComponent) must read back after close")
        }
        XCTAssertEqual(try duration(cp.segmentURLs[1]), 0.2, accuracy: 0.05)
    }

    // MARK: C99 — a kill mid-take

    func testKillMidTakeRebuildsNoteFromSegmentsAndSaysSo() async throws {
        let started = Date(timeIntervalSince1970: 1_790_000_000)
        let cp = RecordingCheckpoint(directory: dir, takeID: "KILL", settings: settings,
                                     sampleRate: rate, segmentSeconds: 60, startedAt: started)
        // The main file, open and never closed — what a kill leaves behind.
        let main = try AVAudioFile(forWriting: cp.mainURL, settings: settings)
        for _ in 0..<3 {
            let b = tone(seconds: 0.5)
            try main.write(from: b)
            try cp.write(b)
            cp.rotate(reason: "interrupt")
        }
        try cp.write(tone(seconds: 0.3))   // in-progress segment, never closed
        try pretendPreviousRun(cp)
        XCTAssertFalse(RecordingCheckpoint.isReadableAudio(cp.mainURL),
                       "precondition: an unclosed m4a is unreadable — the whole reason for segments")

        let repo = NotesRepository(inMemory: true)
        let report = await saver(repo).recoverInterruptedRecordings(directory: dir)
        track(repo, report.recovered)

        XCTAssertEqual(report.recovered.count, 1)
        let memo = try XCTUnwrap(report.recovered.first.flatMap { repo.memo(id: $0) })
        XCTAssertEqual(memo.title, MemoSaver.recoveredTitle, "the rebuilt note says it was recovered")
        XCTAssertEqual(memo.transcriptStatus, .transcribing, "the launch transcription recovery picks it up")
        XCTAssertEqual(memo.recordedAt, started)
        XCTAssertEqual(memo.duration, 1.5, accuracy: 0.1, "all audio up to the last closed segment")
        XCTAssertEqual(RecordingCheckpoint.takeFiles(take: "KILL", in: dir), [], "take files consumed")
        withExtendedLifetime(main) {}
    }

    func testForceQuitFinalizedMainFileIsPreferred() async throws {
        let cp = RecordingCheckpoint(directory: dir, takeID: "QUIT", settings: settings,
                                     sampleRate: rate, segmentSeconds: 60)
        let main = try AVAudioFile(forWriting: cp.mainURL, settings: settings)
        let b = tone(seconds: 0.8)
        try main.write(from: b)
        try cp.write(tone(seconds: 0.4))
        main.close()
        cp.finalize()                      // what willTerminate does
        try pretendPreviousRun(cp)

        let sources = MemoSaver.recoverableSources(take: "QUIT", marker: cp.marker.with(session: "previous-run"), in: dir)
        XCTAssertEqual(sources.map(\.lastPathComponent), ["rec_tmp_QUIT.m4a"])

        let repo = NotesRepository(inMemory: true)
        let report = await saver(repo).recoverInterruptedRecordings(directory: dir)
        track(repo, report.recovered)
        let memo = try XCTUnwrap(report.recovered.first.flatMap { repo.memo(id: $0) })
        XCTAssertEqual(memo.duration, 0.8, accuracy: 0.1, "the whole main file, not just the segments")
    }

    func testLiveTakeOfThisRunIsNeverSwept() async throws {
        let cp = RecordingCheckpoint(directory: dir, takeID: "LIVE", settings: settings,
                                     sampleRate: rate, segmentSeconds: 60)
        try cp.write(tone(seconds: 0.3))
        cp.rotate(reason: "background")
        let repo = NotesRepository(inMemory: true)
        let report = await saver(repo).recoverInterruptedRecordings(directory: dir)
        XCTAssertEqual(report, MemoSaver.RecordingSweepReport())
        XCTAssertTrue(FileManager.default.fileExists(atPath: cp.markerURL.path))
    }

    // MARK: C288 — cleanup after a failed sweep

    func testUnrecoverableTakesAreCleanedAfterAFailedSweep() async throws {
        let cp = RecordingCheckpoint(directory: dir, takeID: "DEAD", settings: settings,
                                     sampleRate: rate, segmentSeconds: 60)
        try Data("not audio".utf8).write(to: cp.mainURL)
        try Data().write(to: dir.appendingPathComponent("rec_seg_DEAD_001.m4a"))
        try pretendPreviousRun(cp)
        // A marker-less orphan from before segments existed.
        try Data("junk".utf8).write(to: dir.appendingPathComponent("rec_tmp_ORPHAN.m4a"))
        // Someone else's file in the same folder is never touched.
        try Data("keep".utf8).write(to: dir.appendingPathComponent("memo_keep.m4a"))

        let repo = NotesRepository(inMemory: true)
        let report = await saver(repo).recoverInterruptedRecordings(directory: dir)

        XCTAssertEqual(report.recovered, [])
        XCTAssertEqual(Set(report.cleaned), ["DEAD", "ORPHAN"])
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: dir.path), ["memo_keep.m4a"])
        XCTAssertTrue(repo.allMemos().isEmpty, "no husk note for a take with no audio")
    }

    // MARK: C263 — never over a transcriptUserEdited memo

    func testTranscriptionRecoveryNeverRunsOverAUserEditedMemo() async throws {
        let repo = NotesRepository(inMemory: true)
        let edited = Memo(audioFilename: "memo_c263_edited_\(UUID().uuidString).m4a")
        edited.transcript = "my own words"
        edited.transcriptUserEdited = true
        edited.transcriptStatus = .transcribing      // killed mid-append
        let plain = Memo(audioFilename: "memo_c263_plain_\(UUID().uuidString).m4a")
        plain.transcriptStatus = .transcribing
        for m in [edited, plain] {
            let url = AppPaths.recordingsDirectory.appendingPathComponent(m.audioFilename)
            FileManager.default.createFile(atPath: url.path, contents: Data())
            createdMemoFiles.append(url)
            repo.insert(m)
        }
        repo.save()

        await saver(repo, text: "engine words").recoverStuckTranscriptions()

        XCTAssertEqual(repo.memo(id: edited.id)?.transcript, "my own words")
        XCTAssertEqual(repo.memo(id: edited.id)?.transcriptStatus, .done, "released from the spinner, text untouched")
        XCTAssertEqual(repo.memo(id: plain.id)?.transcript, "engine words", "an unedited stuck memo still recovers")
    }

    // MARK: D131 — low memory saves the recording first

    func testMemoryWarningSavesTheRecordingBeforeUnloadingTheTranscriber() {
        XCTAssertEqual(LiveRecordingService.memoryWarningOrder,
                       [.flushAudio, .writeCheckpoint, .stopCaptions, .unloadTranscriber])
    }

    // MARK: R46 — a failed write surfaces, never a silent try?

    func testSegmentWriteFailureThrows() throws {
        let gone = dir.appendingPathComponent("missing", isDirectory: true)
        let cp = RecordingCheckpoint(directory: gone, takeID: "FULL", settings: settings,
                                     sampleRate: rate, segmentSeconds: 60)
        XCTAssertThrowsError(try cp.write(tone(seconds: 0.1)))
        XCTAssertFalse(LiveRecordingService.diskFullMessage.isEmpty)
    }

    // MARK: C287 — Release-safe lifecycle lines

    func testLifecycleTransitionsLogToOSLog() throws {
        let cp = RecordingCheckpoint(directory: dir, takeID: "LOG", settings: settings,
                                     sampleRate: rate, segmentSeconds: 60)
        try cp.write(tone(seconds: 0.2))
        let since = Date().addingTimeInterval(-5)
        cp.rotate(reason: "interrupt")
        XCTAssertTrue(RecordingLifecycleLog.recent.contains { $0.contains("rec segment") && $0.contains("take=LOG") })

        let store = try OSLogStore(scope: .currentProcessIdentifier)
        let entries = try store.getEntries(at: store.position(date: since),
                                           matching: NSPredicate(format: "subsystem == %@", RecordingLifecycleLog.subsystem))
        let lines = entries.compactMap { $0 as? OSLogEntryLog }.map(\.composedMessage)
        XCTAssertTrue(lines.contains { $0.contains("rec segment") && $0.contains("take=LOG") },
                      "the segment line is in the unified log (os_log), not only DevLog; got \(lines.suffix(5))")
    }
}

private extension RecordingMarker {
    func with(session: String) -> RecordingMarker {
        var m = self
        m.sessionID = session
        return m
    }
}
