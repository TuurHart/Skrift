import XCTest
@testable import SkriftMobile

/// Pure micro-scrubber math (`CaptureScrub`): drag latching (which handle a
/// drag moves is decided ONCE, at gesture start), no-cross clamping with the
/// minimum span, x↔time mapping, and the pannable window (background pan +
/// handle edge-bump), all inside the file's bounds.
final class AudiobookScrubberTests: XCTestCase {

    private typealias Span = CaptureSpan.Span

    private let bounds = Span(start: 0, end: 3600)

    // MARK: - Latch (the "OUT jumps while dragging toward IN" bug)

    func testLatchClaimsFirstHandleAndRefusesTheOther() {
        var latch = CaptureScrub.Latch()
        XCTAssertNil(latch.active)
        XCTAssertTrue(latch.claim(.inMarker), "a free latch is claimed by the first drag")
        XCTAssertFalse(latch.claim(.outMarker), "a second touch can't steal the drag")
        XCTAssertTrue(latch.claim(.inMarker), "the owner keeps re-claiming per move")
        XCTAssertEqual(latch.active, .inMarker)
    }

    func testLatchReleasesOnlyByOwner() {
        var latch = CaptureScrub.Latch()
        XCTAssertTrue(latch.claim(.outMarker))
        latch.release(.inMarker)   // the losing gesture's stray onEnded
        XCTAssertEqual(latch.active, .outMarker, "a non-owner release must not free the latch")
        latch.release(.outMarker)
        XCTAssertNil(latch.active)
        XCTAssertTrue(latch.claim(.inMarker), "free again after the owner releases")
    }

    // MARK: - Handle clamping (no crossing, minimum span, bounds)

    func testDraggedInTowardOutStopsAtMinimumSpan() {
        let span = Span(start: 100, end: 130)
        let s = CaptureScrub.dragged(span, handle: .inMarker, to: 129.5, bounds: bounds)
        XCTAssertEqual(s.start, 129, "IN stops one second before OUT")
        XCTAssertEqual(s.end, 130, "OUT never moves on an IN drag")
    }

    func testDraggedOutTowardInStopsAtMinimumSpan() {
        let span = Span(start: 100, end: 130)
        let s = CaptureScrub.dragged(span, handle: .outMarker, to: 50, bounds: bounds)
        XCTAssertEqual(s.end, 101, "OUT stops one second after IN")
        XCTAssertEqual(s.start, 100, "IN never moves on an OUT drag")
    }

    func testDraggedClampsToBounds() {
        let span = Span(start: 100, end: 130)
        XCTAssertEqual(
            CaptureScrub.dragged(span, handle: .inMarker, to: -50, bounds: bounds).start, 0
        )
        XCTAssertEqual(
            CaptureScrub.dragged(span, handle: .outMarker, to: 9999, bounds: bounds).end, 3600
        )
    }

    // MARK: - Window-confined drag (round 2: no edge-bump runaway)

    func testWindowConfinedDragPinsAtTheWindowEdge() {
        // The device finding: dragging OUT past the strip's edge used to
        // edge-bump the window along and run the span to pause+256 s. Now the
        // handle pins at the visible window's edge instead.
        let window = Span(start: 100, end: 175)
        let span = Span(start: 130, end: 160)
        let s = CaptureScrub.dragged(
            span, handle: .outMarker, to: 9999, within: window, bounds: bounds
        )
        XCTAssertEqual(s.end, 175, "OUT pins at the window edge, not the file edge")
        XCTAssertEqual(s.start, 130)

        let s2 = CaptureScrub.dragged(
            span, handle: .inMarker, to: -9999, within: window, bounds: bounds
        )
        XCTAssertEqual(s2.start, 100, "IN pins at the window edge")
        XCTAssertEqual(s2.end, 160)
    }

    func testWindowConfinedDragInsideTheWindowIsUnchangedBehavior() {
        let window = Span(start: 100, end: 175)
        let span = Span(start: 130, end: 160)
        let s = CaptureScrub.dragged(
            span, handle: .inMarker, to: 112, within: window, bounds: bounds
        )
        XCTAssertEqual(s, Span(start: 112, end: 160))
    }

    func testWindowConfinedDragStillRespectsBoundsAndMinimumSpan() {
        // A window panned to the file's start: the window edge may sit OUTSIDE
        // the bounds-clamp's reach — bounds still win.
        let window = Span(start: -10, end: 65)   // degenerate (pan clamps in
        // practice, but the math must not trust it)
        let span = Span(start: 5, end: 30)
        let s = CaptureScrub.dragged(
            span, handle: .inMarker, to: -9999, within: window, bounds: bounds
        )
        XCTAssertEqual(s.start, 0, "bounds outrank the window")
        // Minimum span survives the window pin too.
        let tight = CaptureScrub.dragged(
            Span(start: 100, end: 101), handle: .outMarker, to: 100,
            within: Span(start: 99, end: 174), bounds: bounds
        )
        XCTAssertEqual(tight.end, 101, "OUT never crosses within a window either")
    }

    func testDraggedRespectsOffsetBounds() {
        // A multi-file book's second file: bounds don't start at 0.
        let fileBounds = Span(start: 600, end: 900)
        let span = Span(start: 700, end: 730)
        XCTAssertEqual(
            CaptureScrub.dragged(span, handle: .inMarker, to: 10, bounds: fileBounds).start, 600,
            "IN can't leave the file"
        )
        XCTAssertEqual(
            CaptureScrub.dragged(span, handle: .outMarker, to: 2000, bounds: fileBounds).end, 900,
            "OUT can't leave the file"
        )
    }

    func testDraggedOnTinyFileNeverCrosses() {
        // File shorter than the minimum span: the guards must not invert.
        let tiny = Span(start: 0, end: 0.5)
        let span = Span(start: 0, end: 0.5)
        let s1 = CaptureScrub.dragged(span, handle: .inMarker, to: 0.4, bounds: tiny)
        XCTAssertLessThanOrEqual(s1.start, s1.end)
        let s2 = CaptureScrub.dragged(span, handle: .outMarker, to: 0.1, bounds: tiny)
        XCTAssertLessThanOrEqual(s2.start, s2.end)
    }

    // MARK: - x ↔ time mapping

    func testTimeAtXMapsLinearlyAndUnclamped() {
        let window = Span(start: 100, end: 175)   // 75 s on a 300 pt strip
        XCTAssertEqual(CaptureScrub.time(atX: 0, stripWidth: 300, window: window), 100)
        XCTAssertEqual(CaptureScrub.time(atX: 300, stripWidth: 300, window: window), 175)
        XCTAssertEqual(CaptureScrub.time(atX: 150, stripWidth: 300, window: window), 137.5)
        // Past the edges it keeps going — that's what drives the edge-bump.
        XCTAssertEqual(CaptureScrub.time(atX: -40, stripWidth: 300, window: window), 90)
        XCTAssertEqual(CaptureScrub.time(atX: 340, stripWidth: 300, window: window), 185)
    }

    // MARK: - Window panning

    func testPanPreservesLengthAndClampsAtBounds() {
        let window = Span(start: 100, end: 175)
        let left = CaptureScrub.pan(window, by: -50, bounds: bounds)
        XCTAssertEqual(left.start, 50)
        XCTAssertEqual(left.length, 75, accuracy: 0.0001)

        let pinnedLeft = CaptureScrub.pan(window, by: -500, bounds: bounds)
        XCTAssertEqual(pinnedLeft.start, 0)
        XCTAssertEqual(pinnedLeft.length, 75, accuracy: 0.0001)

        let pinnedRight = CaptureScrub.pan(window, by: 99999, bounds: bounds)
        XCTAssertEqual(pinnedRight.end, 3600)
        XCTAssertEqual(pinnedRight.length, 75, accuracy: 0.0001)
    }

    func testPanInsideOffsetBounds() {
        let fileBounds = Span(start: 600, end: 900)
        let window = Span(start: 700, end: 775)
        let pinned = CaptureScrub.pan(window, by: -500, bounds: fileBounds)
        XCTAssertEqual(pinned.start, 600, "the window can't pan before the file")
        XCTAssertEqual(pinned.length, 75, accuracy: 0.0001)
    }

    func testPanWhenBoundsShorterThanWindowCollapsesToBounds() {
        let tiny = Span(start: 0, end: 40)
        let window = Span(start: 0, end: 40)
        let panned = CaptureScrub.pan(window, by: 10, bounds: tiny)
        XCTAssertEqual(panned, tiny)
    }

    func testPannedToIncludeOnlyMovesWhenNeeded() {
        let window = Span(start: 100, end: 175)
        // Inside → untouched.
        XCTAssertEqual(CaptureScrub.panned(toInclude: 150, window: window, bounds: bounds), window)
        // Below → slides left exactly to the target.
        let left = CaptureScrub.panned(toInclude: 80, window: window, bounds: bounds)
        XCTAssertEqual(left.start, 80)
        XCTAssertEqual(left.length, 75, accuracy: 0.0001)
        // Above → slides right exactly to the target.
        let right = CaptureScrub.panned(toInclude: 200, window: window, bounds: bounds)
        XCTAssertEqual(right.end, 200)
        XCTAssertEqual(right.length, 75, accuracy: 0.0001)
        // Target beyond the bounds clamps to the bounds edge.
        let pinned = CaptureScrub.panned(toInclude: -100, window: window, bounds: bounds)
        XCTAssertEqual(pinned.start, 0)
    }

    // MARK: - Bounded proposal / window (multi-file capture confinement)

    func testBoundedProposalClampsToFileStart() {
        let fileBounds = Span(start: 600, end: 900)
        // 10 s into the second file: the lookback can't reach the prior file.
        let span = CaptureSpan.proposal(now: 610, in: fileBounds)
        XCTAssertEqual(span.start, 600)
        XCTAssertEqual(span.end, 610)
    }

    func testBoundedProposalMidFileIsLast30Seconds() {
        let span = CaptureSpan.proposal(now: 800, in: Span(start: 600, end: 900))
        XCTAssertEqual(span.start, 770)
        XCTAssertEqual(span.end, 800)
    }

    func testBoundedProposalAtFileStartOffersMinimalForwardSpan() {
        let span = CaptureSpan.proposal(now: 600, in: Span(start: 600, end: 900))
        XCTAssertEqual(span.start, 600)
        XCTAssertEqual(span.end, 600 + CaptureSpan.minimumSpan)
    }

    func testBoundedWindowClampsToFile() {
        let fileBounds = Span(start: 600, end: 900)
        let w = CaptureSpan.window(now: 620, in: fileBounds)
        XCTAssertEqual(w.start, 600, "the window never reaches the prior file")
        XCTAssertEqual(w.end, 635)

        let end = CaptureSpan.window(now: 895, in: fileBounds)
        XCTAssertEqual(end.end, 900)
        XCTAssertEqual(end.start, 835)
    }

    func testUnboundedVariantsStillMatchLegacyBehavior() {
        // The duration-based entry points delegate to the bounded ones.
        XCTAssertEqual(CaptureSpan.proposal(now: 756, duration: 3600),
                       CaptureSpan.proposal(now: 756, in: Span(start: 0, end: 3600)))
        XCTAssertEqual(CaptureSpan.window(now: 756, duration: 3600),
                       CaptureSpan.window(now: 756, in: Span(start: 0, end: 3600)))
    }
}
