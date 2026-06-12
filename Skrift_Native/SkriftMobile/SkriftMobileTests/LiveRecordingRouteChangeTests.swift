import AVFoundation
import XCTest
@testable import SkriftMobile

/// Pure-logic coverage for the route-change survival path in
/// `LiveRecordingService` (the AirPods pull-out P0): the format-change
/// decision, the tap-install precondition (session-hw vs vended — cross-rate
/// installs ACCEPTED, per the 2026-06-12 DevLog verdict), the rebuild-action
/// decision (stale-cache `engine.reset()` vs not-ready backoff — the round-3
/// refuse-loop deadlock fix), the rebuild backoff + never-give-up re-arm
/// contract, converter selection, conversion continuity across consecutive
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

    // MARK: - Tap-install validation (round-2 P0: InstallTapOnNode raises an
    // UNCATCHABLE NSException on an invalid mid-transition format, so this
    // pure precondition is the only defense. DevLog verdict 2026-06-12 09:14:
    // the check must compare the vended tap format against the SESSION's live
    // hardware format and NEVER against the file's — cross-rate rebuilds are
    // legitimate and the per-tap converter bridges them.)

    func testAcceptsWhenVendedFormatAgreesWithSessionHardware() {
        XCTAssertTrue(LiveRecordingService.canInstallTap(
            sessionHwRate: 48_000, sessionHwChannels: 1, vendedRate: 48_000, vendedChannels: 1))
        XCTAssertTrue(LiveRecordingService.canInstallTap(
            sessionHwRate: 24_000, sessionHwChannels: 2, vendedRate: 24_000, vendedChannels: 2))
    }

    func testAcceptsCrossRateRebuildRegardlessOfFileFormat() {
        // The DEAF-recording bug: a recording started on AirPods (24 kHz file)
        // falls back to the built-in mic (48 kHz hardware). The 48 kHz install
        // MUST be accepted even though it differs from the file's 24 kHz —
        // the per-install converter bridges tap→file. (The old semantics
        // effectively demanded new == old/file format, refused this forever,
        // and the recording went deaf on the new route.)
        XCTAssertTrue(LiveRecordingService.canInstallTap(
            sessionHwRate: 48_000, sessionHwChannels: 1, vendedRate: 48_000, vendedChannels: 1))
        XCTAssertNotNil(LiveRecordingService.makeWriteConverter(
            from: format(rate: 48_000), to: format(rate: 24_000)),
            "the accepted cross-rate install must come with a tap→file bridge")
        // …and the reverse hop (re-insert: back onto AirPods, 48 kHz file).
        XCTAssertTrue(LiveRecordingService.canInstallTap(
            sessionHwRate: 24_000, sessionHwChannels: 1, vendedRate: 24_000, vendedChannels: 1))
        XCTAssertNotNil(LiveRecordingService.makeWriteConverter(
            from: format(rate: 24_000), to: format(rate: 48_000)))
    }

    func testRefusesZeroedMidTransitionFormat() {
        // What the input node reports mid-route-transition (the crash-log case).
        XCTAssertFalse(LiveRecordingService.canInstallTap(
            sessionHwRate: 0, sessionHwChannels: 0, vendedRate: 0, vendedChannels: 0))
        XCTAssertFalse(LiveRecordingService.canInstallTap(
            sessionHwRate: 0, sessionHwChannels: 1, vendedRate: 0, vendedChannels: 1))
        XCTAssertFalse(LiveRecordingService.canInstallTap(
            sessionHwRate: 48_000, sessionHwChannels: 0, vendedRate: 48_000, vendedChannels: 0))
    }

    func testRefusesVendedFormatLaggingSessionHardware() {
        // AirPods pulled: the session is already on the 48 kHz built-in mic but
        // the engine still vends the cached 24 kHz AirPods format — install
        // would capture garbage at the wrong rate. NOT self-settling (round-3
        // DevLog: the cache stays frozen until `engine.reset()`) — the rebuild
        // breaks it via `rebuildAction == .resetThenRequery` (tests below);
        // this validator just keeps refusing the disagreement.
        XCTAssertFalse(LiveRecordingService.canInstallTap(
            sessionHwRate: 48_000, sessionHwChannels: 1, vendedRate: 24_000, vendedChannels: 1))
        XCTAssertFalse(LiveRecordingService.canInstallTap(
            sessionHwRate: 48_000, sessionHwChannels: 1, vendedRate: 48_000, vendedChannels: 2))
    }

    // MARK: - Rebuild action (round-3 DevLog 2026-06-12 09:40: the refuse-loop
    // DEADLOCK — after a route flip the input node kept vending the old format
    // across every backoff retry, because AVAudioEngine caches node formats
    // until `engine.reset()`. The rebuild must reset-then-requery FIRST on
    // each attempt whenever the live hardware disagrees with the vended
    // format, and only back off when the hardware itself isn't ready.)

    func testAgreeingFormatsInstallWithoutReset() {
        XCTAssertEqual(LiveRecordingService.rebuildAction(
            sessionHwRate: 48_000, sessionHwChannels: 1, vendedRate: 48_000, vendedChannels: 1),
            .install)
        XCTAssertEqual(LiveRecordingService.rebuildAction(
            sessionHwRate: 24_000, sessionHwChannels: 2, vendedRate: 24_000, vendedChannels: 2),
            .install)
    }

    func testStaleVendedFormatForcesResetThenRequery() {
        // The logged round-3 deadlock: route flipped to AirPods (sessionHw
        // 24 kHz) but the engine froze on the cached built-in 48 kHz across
        // every retry — must reset, never just back off.
        XCTAssertEqual(LiveRecordingService.rebuildAction(
            sessionHwRate: 24_000, sessionHwChannels: 1, vendedRate: 48_000, vendedChannels: 1),
            .resetThenRequery)
        // …and the reverse hop (AirPods pulled, cache stuck on 24 kHz).
        XCTAssertEqual(LiveRecordingService.rebuildAction(
            sessionHwRate: 48_000, sessionHwChannels: 1, vendedRate: 24_000, vendedChannels: 1),
            .resetThenRequery)
        // Channel-count disagreement is the same stale cache.
        XCTAssertEqual(LiveRecordingService.rebuildAction(
            sessionHwRate: 48_000, sessionHwChannels: 1, vendedRate: 48_000, vendedChannels: 2),
            .resetThenRequery)
    }

    func testDeadVendedFormatWithLiveHardwareAlsoResets() {
        // Hardware is up but the node vends 0 Hz/0 ch — a cached-dead format
        // is just another stale cache; reset re-queries it.
        XCTAssertEqual(LiveRecordingService.rebuildAction(
            sessionHwRate: 48_000, sessionHwChannels: 1, vendedRate: 0, vendedChannels: 0),
            .resetThenRequery)
    }

    func testDeadHardwareBacksOffInsteadOfResetting() {
        // The genuinely-not-ready case (mid-Bluetooth-handover, no live input):
        // a reset can't conjure a mic — keep the existing backoff + re-arm.
        XCTAssertEqual(LiveRecordingService.rebuildAction(
            sessionHwRate: 0, sessionHwChannels: 0, vendedRate: 0, vendedChannels: 0),
            .backoff)
        XCTAssertEqual(LiveRecordingService.rebuildAction(
            sessionHwRate: 0, sessionHwChannels: 0, vendedRate: 48_000, vendedChannels: 1),
            .backoff)
        XCTAssertEqual(LiveRecordingService.rebuildAction(
            sessionHwRate: 48_000, sessionHwChannels: 0, vendedRate: 48_000, vendedChannels: 1),
            .backoff)
    }

    func testInitialStartRaceRecoversViaResetPlusConverter() {
        // The user's actual failure: record starts on the built-in mic
        // (48 kHz file), the route flips to AirPods ~1 s later. The rebuild
        // sees sessionHw=24 kHz vs the frozen vended=48 kHz → reset-then-
        // requery; the post-reset 24 kHz vended format is accepted and the
        // per-install converter bridges the 24 kHz tap to the 48 kHz file.
        XCTAssertEqual(LiveRecordingService.rebuildAction(
            sessionHwRate: 24_000, sessionHwChannels: 1, vendedRate: 48_000, vendedChannels: 1),
            .resetThenRequery)
        XCTAssertTrue(LiveRecordingService.canInstallTap(
            sessionHwRate: 24_000, sessionHwChannels: 1, vendedRate: 24_000, vendedChannels: 1),
            "post-reset agreeing format must be installable")
        XCTAssertNotNil(LiveRecordingService.makeWriteConverter(
            from: format(rate: 24_000), to: format(rate: 48_000)),
            "the post-reset cross-rate install must come with a tap→file bridge")
    }

    func testResetDecisionIsStateless() {
        // Like canInstallTap, the decision carries no sticky state: any number
        // of reset-then-requery rounds (or refusals) must not poison the
        // eventual agreeing install.
        for _ in 0..<10 {
            XCTAssertEqual(LiveRecordingService.rebuildAction(
                sessionHwRate: 24_000, sessionHwChannels: 1, vendedRate: 48_000, vendedChannels: 1),
                .resetThenRequery)
        }
        XCTAssertEqual(LiveRecordingService.rebuildAction(
            sessionHwRate: 24_000, sessionHwChannels: 1, vendedRate: 24_000, vendedChannels: 1),
            .install)
    }

    func testRefusesWhenOnlyVendedSideLooksAlive() {
        // A live-looking vended format with a dead session (0 Hz/0 ch, e.g.
        // input unavailable) is still a transient — refuse.
        XCTAssertFalse(LiveRecordingService.canInstallTap(
            sessionHwRate: 0, sessionHwChannels: 0, vendedRate: 48_000, vendedChannels: 1))
    }

    // MARK: - Rebuild backoff + re-arm (never a permanent give-up)

    func testRebuildBackoffSpansAboutThreeSecondsThenExhausts() {
        var attempt = 0
        var total = 0
        var previous = 0
        while let delay = LiveRecordingService.rebuildRetryDelayMs(afterAttempt: attempt) {
            XCTAssertGreaterThanOrEqual(delay, previous, "backoff must not shrink")
            total += delay
            previous = delay
            attempt += 1
            XCTAssertLessThan(attempt, 20, "backoff must exhaust (hand-off to the armed observers)")
        }
        XCTAssertGreaterThanOrEqual(attempt, 3, "needs a few in-window retries for a BT handover")
        XCTAssertTrue((2_500...3_500).contains(total), "total backoff ≈3 s, got \(total) ms")
    }

    func testExhaustedBackoffIsNotAPermanentGiveUp() {
        // Past the schedule the delay is nil — the rebuild loop stops, but the
        // decision logic carries NO sticky failure state: after any number of
        // refusals, the very same check accepts the moment a later route /
        // engine-configuration / media-services notification re-triggers a
        // rebuild with a settled format.
        XCTAssertNil(LiveRecordingService.rebuildRetryDelayMs(afterAttempt: 99))
        for _ in 0..<10 {
            XCTAssertFalse(LiveRecordingService.canInstallTap(
                sessionHwRate: 48_000, sessionHwChannels: 1, vendedRate: 24_000, vendedChannels: 1))
        }
        XCTAssertTrue(LiveRecordingService.canInstallTap(
            sessionHwRate: 48_000, sessionHwChannels: 1, vendedRate: 48_000, vendedChannels: 1),
            "a refusal history must never poison a later valid install")
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
