import XCTest
@testable import SkriftMobile

/// Pure Hybrid capture-adjust math (`CaptureMath`):
/// - mark placement with reaction bias
/// - ±1s chip nudging and clamping
/// - seek targets after chip taps
/// - strip x↔time mapping
/// - window extension on ⟲-past-edge
/// - ⟲5 / 5⟳ skip handling
/// - `CaptureSpan.replayWindow` initial window
///
/// Everything here is host-less (no AVFoundation, no UI).
final class AudiobookScrubberTests: XCTestCase {

    private typealias Span = CaptureSpan.Span

    private let bounds = Span(start: 0, end: 3600)

    // MARK: - Mark placement — reaction bias

    func testInMarkWhilePlayingAppliesBias() {
        let mark = CaptureMath.placeInMark(playheadTime: 100, isPlaying: true, bounds: bounds)
        XCTAssertEqual(mark, 100 - CaptureMath.reactionBias, accuracy: 0.001,
                       "IN while playing: mark lands 0.7 s before the playhead")
    }

    func testInMarkWhilePausedIsExact() {
        let mark = CaptureMath.placeInMark(playheadTime: 100, isPlaying: false, bounds: bounds)
        XCTAssertEqual(mark, 100,
                       "IN while paused: mark lands exactly at the playhead")
    }

    func testOutMarkWhilePlayingAppliesBias() {
        let mark = CaptureMath.placeOutMark(playheadTime: 200, isPlaying: true, inMark: nil, bounds: bounds)
        XCTAssertEqual(mark, 200 - CaptureMath.reactionBias, accuracy: 0.001)
    }

    func testOutMarkWhilePausedIsExact() {
        let mark = CaptureMath.placeOutMark(playheadTime: 200, isPlaying: false, inMark: nil, bounds: bounds)
        XCTAssertEqual(mark, 200)
    }

    func testOutMarkEnforcesMinimumSpanAboveInMark() {
        // OUT placed at 100 with IN at 100 — must be pushed forward to IN + 1 s.
        let mark = CaptureMath.placeOutMark(
            playheadTime: 100, isPlaying: false, inMark: 100, bounds: bounds
        )
        XCTAssertEqual(mark, 101, "OUT ≥ IN + minimumSpan")
    }

    func testOutMarkWhilePlayingEnforcesMinimumSpanAfterBias() {
        // Playing, playhead at 100.7 → after bias OUT would land at 100 = IN.
        let mark = CaptureMath.placeOutMark(
            playheadTime: 100.7, isPlaying: true, inMark: 100, bounds: bounds
        )
        // 100.7 - 0.7 = 100, which equals IN → must be pushed to 101.
        XCTAssertGreaterThanOrEqual(mark, 100 + CaptureMath.minimumSpan)
    }

    // MARK: - Clamping to bounds

    func testInMarkClampsToFileStart() {
        let mark = CaptureMath.placeInMark(playheadTime: 0, isPlaying: true, bounds: bounds)
        XCTAssertEqual(mark, 0, "bias can't push IN before the file start")
    }

    func testInMarkClampsToFileEnd() {
        let mark = CaptureMath.placeInMark(playheadTime: 4000, isPlaying: false, bounds: bounds)
        XCTAssertEqual(mark, 3600)
    }

    func testOutMarkClampsToFileEnd() {
        let mark = CaptureMath.placeOutMark(playheadTime: 9999, isPlaying: false, inMark: nil, bounds: bounds)
        XCTAssertEqual(mark, 3600)
    }

    func testMarksWorkOnOffsetBounds() {
        // Multi-file book: second file starts at 600.
        let fileBounds = Span(start: 600, end: 900)
        let inM = CaptureMath.placeInMark(playheadTime: 595, isPlaying: false, bounds: fileBounds)
        XCTAssertEqual(inM, 600, "IN can't leave the file")
        let outM = CaptureMath.placeOutMark(playheadTime: 950, isPlaying: false, inMark: nil, bounds: fileBounds)
        XCTAssertEqual(outM, 900, "OUT can't leave the file")
    }

    // MARK: - ±1s chip nudging

    func testNudgeInBackwardByOneSecond() {
        let result = CaptureMath.nudgeInMark(current: 100, delta: -1, outMark: 110, bounds: bounds)
        XCTAssertEqual(result, 99)
    }

    func testNudgeInForwardByOneSecond() {
        let result = CaptureMath.nudgeInMark(current: 100, delta: 1, outMark: 110, bounds: bounds)
        XCTAssertEqual(result, 101)
    }

    func testNudgeInNeverCrossesOut() {
        // Pushing IN forward toward OUT − 1 s.
        let result = CaptureMath.nudgeInMark(current: 109.5, delta: 1, outMark: 110, bounds: bounds)
        XCTAssertEqual(result, 109, "IN stops at OUT − minimumSpan")
    }

    func testNudgeInClampsToFileStart() {
        let result = CaptureMath.nudgeInMark(current: 0.5, delta: -1, outMark: nil, bounds: bounds)
        XCTAssertEqual(result, 0)
    }

    func testNudgeOutForwardByOneSecond() {
        let result = CaptureMath.nudgeOutMark(current: 110, delta: 1, inMark: 100, bounds: bounds)
        XCTAssertEqual(result, 111)
    }

    func testNudgeOutBackwardByOneSecond() {
        let result = CaptureMath.nudgeOutMark(current: 110, delta: -1, inMark: 100, bounds: bounds)
        XCTAssertEqual(result, 109)
    }

    func testNudgeOutNeverCrossesIn() {
        // Pushing OUT backward toward IN + 1 s.
        let result = CaptureMath.nudgeOutMark(current: 100.5, delta: -1, inMark: 100, bounds: bounds)
        XCTAssertEqual(result, 101, "OUT stops at IN + minimumSpan")
    }

    func testNudgeOutClampsToFileEnd() {
        let result = CaptureMath.nudgeOutMark(current: 3599.5, delta: 1, inMark: nil, bounds: bounds)
        XCTAssertEqual(result, 3600)
    }

    // MARK: - Seek targets after chip taps

    func testInChipSeekTargetIsAtTheNewMark() {
        let target = CaptureMath.inChipSeekTarget(newInMark: 120)
        XCTAssertEqual(target, 120, "IN chip starts playback from the new in-mark")
    }

    func testOutChipSeekTargetIsTailLengthBeforeOut() {
        let target = CaptureMath.outChipSeekTarget(newOutMark: 200, inMark: nil)
        XCTAssertEqual(target, 200 - CaptureMath.outChipTailLength, accuracy: 0.001)
    }

    func testOutChipSeekTargetClampsToInMark() {
        // Short span: outMark is only 2 s after inMark — the tail can't go before inMark.
        let target = CaptureMath.outChipSeekTarget(newOutMark: 102, inMark: 100)
        XCTAssertGreaterThanOrEqual(target, 100, "seek never goes before the in-mark")
    }

    // MARK: - Window extension

    func testExtendWindowLeftByDefaultStep() {
        let window = Span(start: 100, end: 500)
        let extended = CaptureMath.extendWindowLeft(window: window, bounds: bounds)
        XCTAssertEqual(extended.start, 100 - CaptureSpan.windowExtensionStep)
        XCTAssertEqual(extended.end, 500, "right edge (pause point) is unchanged")
    }

    func testExtendWindowLeftClampsToFileStart() {
        let window = Span(start: 20, end: 500)
        let extended = CaptureMath.extendWindowLeft(window: window, bounds: bounds)
        XCTAssertEqual(extended.start, 0, "can't extend past the file start")
    }

    func testExtendWindowLeftOnOffsetBounds() {
        let fileBounds = Span(start: 600, end: 900)
        let window = Span(start: 610, end: 810)
        let extended = CaptureMath.extendWindowLeft(window: window, bounds: fileBounds)
        XCTAssertEqual(extended.start, 600, "clamped to file start in offset bounds")
        XCTAssertEqual(extended.end, 810)
    }

    func testExtendWindowLeftAlreadyAtBoundsStart() {
        let window = Span(start: 0, end: 500)
        let extended = CaptureMath.extendWindowLeft(window: window, bounds: bounds)
        XCTAssertEqual(extended.start, 0, "already at start — no change")
    }

    // MARK: - Strip x ↔ time mapping

    func testTimeAtXMapsLinearly() {
        let window = Span(start: 100, end: 175)   // 75 s on a 300 pt strip
        XCTAssertEqual(CaptureMath.time(atX: 0, stripWidth: 300, window: window), 100)
        XCTAssertEqual(CaptureMath.time(atX: 300, stripWidth: 300, window: window), 175)
        XCTAssertEqual(CaptureMath.time(atX: 150, stripWidth: 300, window: window), 137.5)
    }

    func testTimeAtXIsUnclamped() {
        let window = Span(start: 100, end: 175)
        XCTAssertEqual(CaptureMath.time(atX: -40, stripWidth: 300, window: window), 90,
                       "past the left edge maps past the window — used for extension detection")
        XCTAssertEqual(CaptureMath.time(atX: 340, stripWidth: 300, window: window), 185)
    }

    func testTimeAtXZeroWidthReturnsWindowStart() {
        let window = Span(start: 100, end: 175)
        XCTAssertEqual(CaptureMath.time(atX: 50, stripWidth: 0, window: window), 100)
    }

    func testXPositionRoundTrips() {
        let window = Span(start: 100, end: 175)
        let t = 140.0
        let x = CaptureMath.xPosition(of: t, stripWidth: 300, window: window)
        let back = CaptureMath.time(atX: x, stripWidth: 300, window: window)
        XCTAssertEqual(back, t, accuracy: 0.001)
    }

    // MARK: - ⟲5 / 5⟳ skip handling

    func testSkipForwardMovesPlayhead() {
        let window = Span(start: 100, end: 200)
        let (newTime, extend) = CaptureMath.applySkip(
            playheadTime: 150, delta: 5, window: window, bounds: bounds
        )
        XCTAssertEqual(newTime, 155)
        XCTAssertFalse(extend)
    }

    func testSkipBackwardMovesPlayhead() {
        let window = Span(start: 100, end: 200)
        let (newTime, extend) = CaptureMath.applySkip(
            playheadTime: 150, delta: -5, window: window, bounds: bounds
        )
        XCTAssertEqual(newTime, 145)
        XCTAssertFalse(extend)
    }

    func testSkipBackwardPastWindowLeftEdgeSignalsExtension() {
        let window = Span(start: 100, end: 200)
        let (newTime, extend) = CaptureMath.applySkip(
            playheadTime: 102, delta: -5, window: window, bounds: bounds
        )
        XCTAssertTrue(extend, "skip past the left edge should signal a window extension")
        XCTAssertEqual(newTime, window.start, "playhead pins at the window start")
    }

    func testSkipForwardClampsToBoundsEnd() {
        let window = Span(start: 3500, end: 3600)
        let (newTime, extend) = CaptureMath.applySkip(
            playheadTime: 3598, delta: 5, window: window, bounds: bounds
        )
        XCTAssertEqual(newTime, 3600, "forward skip clamps to file end")
        XCTAssertFalse(extend)
    }

    func testSkipOnOffsetBoundsDoesNotLeaveFIle() {
        let fileBounds = Span(start: 600, end: 900)
        let window = Span(start: 620, end: 900)
        let (newTime, _) = CaptureMath.applySkip(
            playheadTime: 898, delta: 5, window: window, bounds: fileBounds
        )
        XCTAssertEqual(newTime, 900)
    }

    // MARK: - Replay window (initial strip window)

    func testReplayWindowIsLast45SecondsByDefault() {
        let w = CaptureSpan.replayWindow(now: 756, in: Span(start: 0, end: 3600))
        XCTAssertEqual(w.start, 756 - CaptureSpan.replayLookback)
        XCTAssertEqual(w.end, 756, "right edge is always the pause point")
    }

    func testReplayWindowClampsAtFileStart() {
        let w = CaptureSpan.replayWindow(now: 20, in: Span(start: 0, end: 3600))
        XCTAssertEqual(w.start, 0, "can't look back before file start")
        XCTAssertEqual(w.end, 20)
    }

    func testReplayWindowOnOffsetBounds() {
        let fileBounds = Span(start: 600, end: 900)
        let w = CaptureSpan.replayWindow(now: 620, in: fileBounds)
        XCTAssertEqual(w.start, 600, "clamped to file start")
        XCTAssertEqual(w.end, 620)
    }

    func testReplayWindowRightEdgeIsAlwaysPausePoint() {
        for now in [0.0, 5, 31, 800, 3599] {
            let w = CaptureSpan.replayWindow(now: now, in: Span(start: 0, end: 3600))
            XCTAssertEqual(w.end, now, "right edge = pause point (now=\(now))")
        }
    }

    // MARK: - Bounded proposal (multi-file capture confinement, unchanged)

    func testBoundedProposalClampsToFileStart() {
        let fileBounds = Span(start: 600, end: 900)
        let span = CaptureSpan.proposal(now: 610, in: fileBounds)
        XCTAssertEqual(span.start, 600)
        XCTAssertEqual(span.end, 610)
    }

    func testBoundedProposalMidFileIsLast30Seconds() {
        let span = CaptureSpan.proposal(now: 800, in: Span(start: 600, end: 900))
        XCTAssertEqual(span.start, 770)
        XCTAssertEqual(span.end, 800)
    }
}
