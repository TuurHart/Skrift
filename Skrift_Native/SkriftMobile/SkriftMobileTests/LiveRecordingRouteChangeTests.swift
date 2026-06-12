import AVFoundation
import XCTest
@testable import SkriftMobile

/// Pure-logic coverage for the route-change survival path in
/// `LiveRecordingService` (the AirPods pull-out P0): the format-change
/// decision, converter selection, conversion continuity across consecutive
/// buffers, and the cross-feature `isRecordingActive` contract. The actual
/// engine/route behavior (pull AirPods → built-in mic, re-insert → AirPods)
/// is device-verified — the Simulator has neither Bluetooth routes nor the
/// real mic stack.
final class LiveRecordingRouteChangeTests: XCTestCase {

    private func format(rate: Double, channels: AVAudioChannelCount = 1) -> AVAudioFormat {
        AVAudioFormat(standardFormatWithSampleRate: rate, channels: channels)!
    }

    // MARK: - Format-change decision

    func testIdenticalFormatsNeedNoConversion() {
        XCTAssertFalse(LiveRecordingService.needsConversion(
            from: format(rate: 48_000), to: format(rate: 48_000)))
    }

    func testSampleRateChangeNeedsConversion() {
        // The device-verified case: recording started on the AirPods mic
        // (24 kHz Bluetooth) falls back to the built-in mic (48 kHz) — and back.
        XCTAssertTrue(LiveRecordingService.needsConversion(
            from: format(rate: 48_000), to: format(rate: 24_000)))
        XCTAssertTrue(LiveRecordingService.needsConversion(
            from: format(rate: 24_000), to: format(rate: 48_000)))
    }

    func testChannelCountChangeNeedsConversion() {
        XCTAssertTrue(LiveRecordingService.needsConversion(
            from: format(rate: 48_000, channels: 2), to: format(rate: 48_000, channels: 1)))
    }

    // MARK: - Converter selection

    func testNoConverterWhenFormatsMatch() {
        // The common case (the route the recording started on): the write path
        // must stay converter-free, byte-identical to the pre-fix behavior.
        XCTAssertNil(LiveRecordingService.makeWriteConverter(
            from: format(rate: 48_000), to: format(rate: 48_000)))
    }

    func testConverterCreatedWhenFormatsDiffer() {
        XCTAssertNotNil(LiveRecordingService.makeWriteConverter(
            from: format(rate: 48_000), to: format(rate: 24_000)))
    }

    // MARK: - Conversion

    private func sineBuffer(format: AVAudioFormat, frames: AVAudioFrameCount) -> AVAudioPCMBuffer {
        let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buf.frameLength = frames
        for ch in 0..<Int(format.channelCount) {
            let data = buf.floatChannelData![ch]
            for i in 0..<Int(frames) {
                data[i] = sin(Float(i) * 2 * .pi * 440 / Float(format.sampleRate))
            }
        }
        return buf
    }

    /// Feed consecutive buffers through ONE persistent converter, like the
    /// writer queue does — total output must track total input × ratio (modulo
    /// small resampler priming), proving no audio is lost across buffer seams.
    private func assertContinuousConversion(srcRate: Double, dstRate: Double) throws {
        let src = format(rate: srcRate)
        let dst = format(rate: dstRate)
        let converter = try XCTUnwrap(LiveRecordingService.makeWriteConverter(from: src, to: dst))
        let perBuffer: AVAudioFrameCount = 4096
        let count: AVAudioFrameCount = 5
        var totalOut: AVAudioFrameCount = 0
        for _ in 0..<count {
            if let out = LiveRecordingService.convert(
                sineBuffer(format: src, frames: perBuffer), with: converter, to: dst) {
                XCTAssertEqual(out.format.sampleRate, dstRate)
                XCTAssertEqual(out.format.channelCount, dst.channelCount)
                totalOut += out.frameLength
            }
        }
        let expected = Double(count * perBuffer) * dstRate / srcRate
        XCTAssertGreaterThan(Double(totalOut), expected - 600, "audio lost across the converter")
        XCTAssertLessThanOrEqual(Double(totalOut), expected + 64, "converter invented frames")
    }

    func testDownsamplesBuiltInMicToAirPodsFileRate() throws {
        try assertContinuousConversion(srcRate: 48_000, dstRate: 24_000)
    }

    func testUpsamplesAirPodsMicToBuiltInFileRate() throws {
        try assertContinuousConversion(srcRate: 24_000, dstRate: 48_000)
    }

    // MARK: - isRecordingActive (cross-lane contract)

    @MainActor
    func testIsRecordingActiveTracksStartPauseStop() throws {
        XCTAssertFalse(LiveRecordingService.isRecordingActive)
        let service = LiveRecordingService(mock: true, liveTranscription: false)
        try service.start()
        XCTAssertTrue(LiveRecordingService.isRecordingActive)
        service.pause()
        XCTAssertTrue(LiveRecordingService.isRecordingActive, "paused is still an active session")
        service.resume()
        XCTAssertTrue(LiveRecordingService.isRecordingActive)
        _ = service.stop()
        XCTAssertFalse(LiveRecordingService.isRecordingActive)
    }

    @MainActor
    func testIsRecordingActiveClearsOnCancel() throws {
        let service = LiveRecordingService(mock: true, liveTranscription: false)
        try service.start()
        XCTAssertTrue(LiveRecordingService.isRecordingActive)
        service.cancel()
        XCTAssertFalse(LiveRecordingService.isRecordingActive)
    }

    @MainActor
    func testIsRecordingActiveClearsWhenRecorderIsDeallocated() throws {
        // Abnormal dismissal: the recorder deinits without stop()/cancel().
        // The weak active reference must not pin a dead session to "true" —
        // otherwise the audiobook player would ignore remote-play forever.
        var service: LiveRecordingService? = LiveRecordingService(mock: true, liveTranscription: false)
        try service?.start()
        XCTAssertTrue(LiveRecordingService.isRecordingActive)
        service = nil
        XCTAssertFalse(LiveRecordingService.isRecordingActive)
    }
}
