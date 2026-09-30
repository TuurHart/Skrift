import XCTest
import AVFoundation
@testable import SkriftMobile

/// `RecordingCore` — the parts of "record a voice memo" both apps share. The session half
/// can't be shared (`AVAudioSession` doesn't exist on macOS), so these are exactly the
/// things that WOULD have drifted: encoder settings, filenames, the meter, the timer label.
final class RecordingCoreTests: XCTestCase {

    // ── encoder ─────────────────────────────────────────────

    /// AAC/m4a at the INPUT's own rate — the Mac must not quietly record at a different
    /// sample rate from the phone, and resampling on the way in only gives the ASR artefacts.
    func testEncoderSettingsFollowTheInputFormat() {
        let f = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1)!
        let s = RecordingCore.encoderSettings(for: f)
        XCTAssertEqual(s[AVFormatIDKey] as? UInt32, kAudioFormatMPEG4AAC)
        XCTAssertEqual(s[AVSampleRateKey] as? Double, 48_000)
        XCTAssertEqual(s[AVNumberOfChannelsKey] as? AVAudioChannelCount, 1)
        XCTAssertEqual(s[AVEncoderAudioQualityKey] as? Int, AVAudioQuality.high.rawValue)

        let stereo = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 2)!
        let s2 = RecordingCore.encoderSettings(for: stereo)
        XCTAssertEqual(s2[AVSampleRateKey] as? Double, 44_100)
        XCTAssertEqual(s2[AVNumberOfChannelsKey] as? AVAudioChannelCount, 2)
    }

    // ── filename ────────────────────────────────────────────

    /// `memo_<uuid>.m4a` — the shape MemoSaver, AppPaths and the Mac's ingest all expect.
    func testFilenameMatchesThePhoneConvention() {
        let id = UUID()
        XCTAssertEqual(RecordingCore.filename(id: id), "memo_\(id.uuidString).m4a")
        XCTAssertEqual(RecordingCore.filename(id: id, ext: "wav"), "memo_\(id.uuidString).wav")
        XCTAssertNotEqual(RecordingCore.filename(), RecordingCore.filename(), "each take is its own file")
    }

    // ── meter ───────────────────────────────────────────────

    /// Silence reads 0, speech-ish RMS reads near full, and nothing exceeds 1 — the ×12
    /// scale is what stops the Mac's bars looking dead next to the phone's.
    func testLevelScalesSpeechToAUsefulRange() {
        XCTAssertEqual(level(of: 0), 0, accuracy: 0.001)
        // RMS 0.08 ≈ comfortable speech → most of the bar.
        XCTAssertGreaterThan(level(of: 0.08), 0.8)
        // Loud input clamps rather than overflowing the bar.
        XCTAssertEqual(level(of: 0.5), 1, accuracy: 0.001)
        XCTAssertEqual(level(of: 1.0), 1, accuracy: 0.001)
    }

    func testLevelOfAnEmptyBufferIsZero() {
        let f = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1)!
        let empty = AVAudioPCMBuffer(pcmFormat: f, frameCapacity: 128)!
        empty.frameLength = 0
        XCTAssertEqual(RecordingCore.level(empty), 0)
    }

    /// The window scrolls; it never rescales. A meter that re-fits its own history reads as
    /// noise rather than as level.
    func testMeterIsAFixedWidthRollingWindow() {
        var m = RecordingCore.Meter(width: 4)
        XCTAssertEqual(m.bars.count, 4)
        XCTAssertEqual(m.bars, [0, 0, 0, 0])
        m.push(1); m.push(0.5)
        XCTAssertEqual(m.bars.count, 4)
        XCTAssertEqual(m.bars, [0, 0, 1, 0.5])
        m.push(0.25); m.push(0); m.push(0.75)
        XCTAssertEqual(m.bars, [0.5, 0.25, 0, 0.75], "oldest falls off the front")
    }

    /// A quiet moment still draws a hairline — a gap would read as "stopped", not "quiet".
    func testMeterHeightIsFlooredAndBounded() {
        var m = RecordingCore.Meter(width: 3)
        m.push(0)
        XCTAssertEqual(m.height(at: 2), 0.12, accuracy: 0.001)
        m.push(1)
        XCTAssertEqual(m.height(at: 2), 1.0, accuracy: 0.001)
        // Out-of-range indices must not trap — SwiftUI can ask mid-resize.
        XCTAssertEqual(m.height(at: -1), 0.12, accuracy: 0.001)
        XCTAssertEqual(m.height(at: 99), 0.12, accuracy: 0.001)
    }

    func testMeterClampsPushedValues() {
        var m = RecordingCore.Meter(width: 2)
        m.push(5); m.push(-3)
        XCTAssertEqual(m.bars, [1, 0])
    }

    // ── timer label ─────────────────────────────────────────

    func testElapsedLabelFormats() {
        XCTAssertEqual(RecordingCore.elapsedLabel(0), "0:00")
        XCTAssertEqual(RecordingCore.elapsedLabel(7), "0:07")
        XCTAssertEqual(RecordingCore.elapsedLabel(67), "1:07")
        XCTAssertEqual(RecordingCore.elapsedLabel(600), "10:00")
        XCTAssertEqual(RecordingCore.elapsedLabel(3600), "1:00:00")
        XCTAssertEqual(RecordingCore.elapsedLabel(3725), "1:02:05")
    }

    /// A negative elapsed (a clock that stepped backwards mid-take) must read 0:00, never
    /// "-1:-3".
    func testElapsedLabelFloorsAtZero() {
        XCTAssertEqual(RecordingCore.elapsedLabel(-5), "0:00")
    }

    // MARK: - helper

    /// A buffer whose every sample is `v`, so its RMS is exactly `v`.
    private func level(of v: Float) -> Float {
        let f = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1)!
        let buf = AVAudioPCMBuffer(pcmFormat: f, frameCapacity: 256)!
        buf.frameLength = 256
        for i in 0..<256 { buf.floatChannelData![0][i] = v }
        return RecordingCore.level(buf)
    }
}
