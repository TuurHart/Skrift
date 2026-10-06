import AVFoundation
import XCTest

/// Q328 (D182, mocks/Q289-mac-recorder-pause.html): the x asks "Discard this recording?"; the
/// take PAUSES while it asks, Keep resumes it, Discard throws it away (main file, segments,
/// marker — C99: nothing is left for the launch sweep to "recover"). No microphone: the take is
/// a fake whose files are real `RecordingCheckpoint` segments in a temp directory.
@MainActor
final class MacRecorderDiscardTests: XCTestCase {

    /// A take with real segment files on disk. `discardTake` is the same file deletion the
    /// recorder's cancel path ends in (`RecordingCheckpoint.discardTakeFiles`).
    @MainActor
    final class FakeTake: DiscardableTake {
        var isPaused = false
        var pauses = 0, resumes = 0, discards = 0
        let takeID = UUID().uuidString
        let directory: URL

        init(directory: URL) { self.directory = directory }

        func pauseTake() { isPaused = true; pauses += 1 }
        func resumeTake() { isPaused = false; resumes += 1 }
        func discardTake() {
            discards += 1
            RecordingCheckpoint.discardTakeFiles(take: takeID, in: directory)
        }

        /// Two 1 s segments + the marker, written through the real checkpoint.
        func writeSegments() throws {
            let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48_000,
                                       channels: 1, interleaved: false)!
            let cp = RecordingCheckpoint(directory: directory, takeID: takeID,
                                         settings: RecordingCore.encoderSettings(for: format),
                                         sampleRate: format.sampleRate, segmentSeconds: 1, startedAt: Date())
            for _ in 0..<2 {
                let n = AVAudioFrameCount(format.sampleRate)
                let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: n)!
                buf.frameLength = n
                let ch = buf.floatChannelData![0]
                for i in 0..<Int(n) { ch[i] = Float(0.3 * sin(2 * Double.pi * 440 * Double(i) / format.sampleRate)) }
                try cp.write(buf)
            }
            cp.rotate(reason: "test")
        }
    }

    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("discard-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDown() { try? FileManager.default.removeItem(at: dir) }

    func testAskingPausesTheTake() {
        let take = FakeTake(directory: dir)
        let ask = RecorderDiscardAsk(take: take)

        ask.ask()

        XCTAssertTrue(ask.isAsking)
        XCTAssertTrue(take.isPaused, "the take must not keep recording while the question is up (D182)")
        XCTAssertEqual(take.pauses, 1)
    }

    func testKeepResumesATakeThatWasRecording() throws {
        let take = FakeTake(directory: dir)
        try take.writeSegments()
        let ask = RecorderDiscardAsk(take: take)

        ask.ask()
        ask.keep()

        XCTAssertFalse(ask.isAsking)
        XCTAssertFalse(take.isPaused, "Keep carries on recording")
        XCTAssertEqual(take.resumes, 1)
        XCTAssertEqual(take.discards, 0)
        XCTAssertFalse(RecordingCheckpoint.takeFiles(take: take.takeID, in: dir).isEmpty,
                       "Keep must not touch the segments")
    }

    func testKeepLeavesATakeThatWasAlreadyPausedPaused() {
        let take = FakeTake(directory: dir)
        take.isPaused = true
        let ask = RecorderDiscardAsk(take: take)

        ask.ask()
        XCTAssertEqual(take.pauses, 0, "already paused: nothing to pause")
        ask.keep()

        XCTAssertTrue(take.isPaused, "the person paused it; Keep gives it back as it was")
        XCTAssertEqual(take.resumes, 0)
    }

    func testDiscardDeletesTheSegmentsAndTheMarker() throws {
        let take = FakeTake(directory: dir)
        try take.writeSegments()
        XCTAssertGreaterThanOrEqual(RecordingCheckpoint.takeFiles(take: take.takeID, in: dir).count, 2,
                                    "fixture: segments + marker are on disk")
        let ask = RecorderDiscardAsk(take: take)

        ask.ask()
        ask.discard()

        XCTAssertFalse(ask.isAsking)
        XCTAssertEqual(take.discards, 1)
        XCTAssertEqual(take.resumes, 0, "a discarded take is not resumed first")
        XCTAssertTrue(RecordingCheckpoint.takeFiles(take: take.takeID, in: dir).isEmpty,
                      "nothing may be left for the launch sweep to bring back as a recovered note")
    }

    func testPressingTheXAgainWhileAskingIsKeep() {
        let take = FakeTake(directory: dir)
        let ask = RecorderDiscardAsk(take: take)

        ask.ask()
        ask.ask()

        XCTAssertFalse(ask.isAsking)
        XCTAssertFalse(take.isPaused)
        XCTAssertEqual(take.discards, 0)
    }

    func testKeepAndDiscardWithNoQuestionOpenDoNothing() {
        let take = FakeTake(directory: dir)
        let ask = RecorderDiscardAsk(take: take)

        ask.keep()
        ask.discard()

        XCTAssertEqual(take.resumes + take.pauses + take.discards, 0,
                       "the popover's dismissal binding fires keep() after a Discard; it must be inert")
    }

    func testTheTakeEndingByAnotherRoadClosesTheQuestionWithoutResuming() {
        let take = FakeTake(directory: dir)
        let ask = RecorderDiscardAsk(take: take)

        ask.ask()
        ask.reset()          // Stop / a write failure ended the take
        ask.keep()           // the popover's dismissal fires afterwards

        XCTAssertFalse(ask.isAsking)
        XCTAssertEqual(take.resumes, 0, "never resume a take that has ended")
    }

    func testTheRecorderItselfIgnoresPauseAndResumeWithNoTake() {
        let recorder = MacRecorder()

        recorder.pause()
        XCTAssertFalse(recorder.isPaused, "nothing recording, nothing to pause")
        recorder.resume()
        XCTAssertFalse(recorder.isPaused)
        XCTAssertEqual(recorder.elapsed, 0)
    }
}
