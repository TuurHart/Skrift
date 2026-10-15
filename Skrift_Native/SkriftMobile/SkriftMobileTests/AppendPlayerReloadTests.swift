import XCTest
import AVFoundation
import SwiftData
@testable import SkriftMobile

/// Q453 (C223): Add recording splices the take onto the note's own `memo_<id>.m4a` IN PLACE, so
/// the open note's player (`AudioPlayerModel`, phone and iPad alike) saw the same URL and kept
/// the pre-append file: playback stopped at the old end until the note was reopened. After an
/// append the open note's player must hold the merged file.
@MainActor
final class AppendPlayerReloadTests: XCTestCase {

    private let fm = FileManager.default
    private var cleanup: [URL] = []
    override func tearDown() {
        cleanup.forEach { try? fm.removeItem(at: $0) }
        cleanup = []
        super.tearDown()
    }

    private let rate: Double = 44_100

    /// A real AAC clip (the recorder's format), `seconds` long.
    private func aacClip(_ url: URL, seconds: Double) throws {
        let settings: [String: Any] = [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: rate,
                                       AVNumberOfChannelsKey: 1,
                                       AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue]
        let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1)!
        let frames = AVAudioFrameCount(rate * seconds)
        let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buf.frameLength = frames
        let ch = buf.floatChannelData![0]
        for i in 0..<Int(frames) { ch[i] = 0.3 * sinf(Float(i) * 2 * .pi * 440 / Float(rate)) }
        let file = try AVAudioFile(forWriting: url, settings: settings)
        try file.write(from: buf)
        cleanup.append(url)
    }

    private func fileSeconds(_ url: URL) throws -> Double {
        let f = try AVAudioFile(forReading: url)
        return Double(f.length) / f.processingFormat.sampleRate
    }

    /// A voice note with `seconds` of real audio at its own `memo_<id>.m4a`.
    private func voiceNote(_ repo: NotesRepository, seconds: Double) throws -> Memo {
        let memo = try Memo.newTyped(into: repo.context)
        let name = "memo_\(memo.id.uuidString).m4a"
        try aacClip(AppPaths.recordingsDirectory.appendingPathComponent(name), seconds: seconds)
        memo.audioFilename = name
        memo.duration = seconds
        memo.transcript = "Before the join."
        memo.transcriptStatus = .done
        try repo.context.save()
        return memo
    }

    private func saver(_ repo: NotesRepository, timings: WordTimingsStore) -> MemoSaver {
        MemoSaver(repository: repo, transcriber: SeededTranscriber(text: "after the join"),
                  wordTimings: timings, metadataProvider: MockMetadataService())
    }

    func testOpenNotesPlayerHoldsTheMergedFileAfterAnAppend() async throws {
        let repo = NotesRepository(inMemory: true)
        let memo = try voiceNote(repo, seconds: 1.0)
        let audio = try XCTUnwrap(memo.audioURL)

        // The note is open: its player loaded the pre-append file.
        let player = AudioPlayerModel()
        player.load(audio)
        XCTAssertTrue(player.hasAudio)
        XCTAssertEqual(player.duration, 1.0, accuracy: 0.1, "precondition: the old length")

        let clip = fm.temporaryDirectory.appendingPathComponent("clip_\(UUID().uuidString).m4a")
        try aacClip(clip, seconds: 1.0)
        let store = WordTimingsStore(directory: fm.temporaryDirectory
            .appendingPathComponent("wt_\(UUID().uuidString)", isDirectory: true))
        await saver(repo, timings: store).appendRecordingAsync(to: memo.id, tempURL: clip)

        let merged = try fileSeconds(audio)
        XCTAssertGreaterThan(merged, 1.9, "precondition: the take was spliced onto the note's audio")
        XCTAssertEqual(player.duration, merged, accuracy: 0.1,
                       "the open note's player plays the merged file, past the old end")
        XCTAssertTrue(player.hasAudio)
        XCTAssertEqual(player.url, audio)
        // C223: the appended words' timings sit past the precise base duration.
        let timings = try XCTUnwrap(store.load(for: memo.id))
        XCTAssertGreaterThanOrEqual(timings.first?.start ?? 0, 0.9)
    }

    func testThePlayerKeepsItsPositionAcrossTheReload() throws {
        let repo = NotesRepository(inMemory: true)
        let memo = try voiceNote(repo, seconds: 1.0)
        let audio = try XCTUnwrap(memo.audioURL)
        let player = AudioPlayerModel()
        player.load(audio)
        player.seek(to: 0.6)

        let clip = fm.temporaryDirectory.appendingPathComponent("clip_\(UUID().uuidString).m4a")
        try aacClip(clip, seconds: 1.0)
        _ = try AudioClipMerge.append(base: audio, addition: clip)
        NotificationCenter.default.post(name: AudioPlayerModel.audioFileDidChange, object: audio)

        XCTAssertEqual(player.duration, try fileSeconds(audio), accuracy: 0.1)
        XCTAssertEqual(player.currentTime, 0.6, accuracy: 0.05, "the reload never jumps back to the start")
    }

    func testAnotherFileChangingLeavesThePlayerAlone() throws {
        let repo = NotesRepository(inMemory: true)
        let memo = try voiceNote(repo, seconds: 1.0)
        let other = try voiceNote(repo, seconds: 1.0)
        let player = AudioPlayerModel()
        player.load(memo.audioURL)

        let otherAudio = try XCTUnwrap(other.audioURL)
        let clip = fm.temporaryDirectory.appendingPathComponent("clip_\(UUID().uuidString).m4a")
        try aacClip(clip, seconds: 1.0)
        _ = try AudioClipMerge.append(base: otherAudio, addition: clip)
        NotificationCenter.default.post(name: AudioPlayerModel.audioFileDidChange, object: otherAudio)

        XCTAssertEqual(player.duration, 1.0, accuracy: 0.1)
        XCTAssertEqual(player.url, memo.audioURL)
    }
}
