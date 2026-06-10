import AVFoundation
import XCTest
@testable import SkriftMobile

/// Regression tests for the "opening a memo stops Spotify" bug: loading audio
/// must not touch the shared `AVAudioSession` — only Play claims it.
final class AudioPlayerModelTests: XCTestCase {

    private var fileURL: URL!

    override func setUpWithError() throws {
        fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("apm_\(UUID().uuidString).caf")
        try Self.writeSilence(to: fileURL)
    }

    override func tearDownWithError() throws {
        if let fileURL { try? FileManager.default.removeItem(at: fileURL) }
    }

    /// Half a second of silence — enough for AVAudioPlayer to report a duration.
    /// (The AVAudioFile flushes when it deinits at the end of the function.)
    private static func writeSilence(to url: URL) throws {
        let format = AVAudioFormat(standardFormatWithSampleRate: 16000, channels: 1)!
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 8000) else {
            throw NSError(domain: "AudioPlayerModelTests", code: 1)
        }
        buffer.frameLength = 8000
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        try file.write(from: buffer)
    }

    @MainActor
    func testLoadDoesNotClaimTheAudioSession() {
        // Opening a memo must not interrupt other apps' audio: load() may not
        // reconfigure or activate the session (that's play()'s job). The old code
        // called prepareToPlay() + setCategory(.playback) here, which stopped
        // music on note open.
        let before = AVAudioSession.sharedInstance().category
        let model = AudioPlayerModel()
        model.load(fileURL)
        XCTAssertTrue(model.hasAudio)
        XCTAssertGreaterThan(model.duration, 0)
        XCTAssertEqual(AVAudioSession.sharedInstance().category, before)
        model.stopAndClear()
    }

    @MainActor
    func testPlayClaimsTheSessionAndStopResetsState() {
        let model = AudioPlayerModel()
        model.load(fileURL)
        model.play()
        XCTAssertTrue(model.isPlaying)
        XCTAssertEqual(AVAudioSession.sharedInstance().category, .playback)
        model.stopAndClear()
        XCTAssertFalse(model.isPlaying)
        XCTAssertFalse(model.hasAudio)
        XCTAssertEqual(model.currentTime, 0)
    }

    @MainActor
    func testMissingFileLoadsToDisabledState() {
        let model = AudioPlayerModel()
        model.load(FileManager.default.temporaryDirectory.appendingPathComponent("nope_\(UUID().uuidString).m4a"))
        XCTAssertFalse(model.hasAudio)
        XCTAssertEqual(model.duration, 0)
    }
}
