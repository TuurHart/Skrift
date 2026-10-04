import AVFoundation
import XCTest

/// Q219 / C239: the shared `AVAudioFile.seconds` and `Transcribing.transcribeRetrying`
/// (one copy for the phone's recorder/import/share paths and the Mac's ingest).
final class AudioFileSecondsAndRetryTests: XCTestCase {

    func testSecondsIsFramesOverFileSampleRate() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("q219_\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: url) }
        let format = AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1)!
        do {
            let out = try AVAudioFile(forWriting: url, settings: format.settings)
            let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 24_000)!
            buf.frameLength = 24_000
            try out.write(from: buf)
        }
        let f = try AVAudioFile(forReading: url)
        XCTAssertEqual(f.seconds, 1.5, accuracy: 0.001)
    }

    private final class FlakyTranscriber: Transcribing, @unchecked Sendable {
        var failuresLeft: Int
        var calls = 0
        init(failures: Int) { failuresLeft = failures }
        func transcribe(audioURL: URL, imageManifest: [ImageManifestEntry]) async throws -> TranscriptionResult {
            calls += 1
            if failuresLeft > 0 {
                failuresLeft -= 1
                throw NSError(domain: "q219", code: 1)
            }
            return TranscriptionResult(text: "ok", confidence: 1, durationMs: 0,
                                       wordTimings: [], markersInjected: false)
        }
    }

    private let clip = URL(fileURLWithPath: "/nonexistent/q219.m4a")

    func testRetriesUntilFirstSuccess() async {
        let t = FlakyTranscriber(failures: 2)
        let r = await t.transcribeRetrying(audioURL: clip, delays: [0, 0, 0, 0])
        XCTAssertEqual(r?.text, "ok")
        XCTAssertEqual(t.calls, 3)
    }

    func testNilAfterEveryAttemptFails() async {
        let t = FlakyTranscriber(failures: 10)
        let r = await t.transcribeRetrying(audioURL: clip, delays: [0, 0, 0])
        XCTAssertNil(r)
        XCTAssertEqual(t.calls, 3)
    }

    func testEmptyDelaysMeansOneImmediateTry() async {
        let t = FlakyTranscriber(failures: 10)
        let r = await t.transcribeRetrying(audioURL: clip, delays: [])
        XCTAssertNil(r)
        XCTAssertEqual(t.calls, 1)
    }
}
