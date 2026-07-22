import XCTest
@testable import SkriftMobile

/// `BookTextDisplay` — the pure display-logic layer behind `BookTextSheet` (mock
/// `book-text-sheet.html` variant B, `LANES-2026-07-22D/BASE.md`). Fixtures build
/// `BookTextSummary.PerText` values inline (no store IO, no `BookAlignmentRunner` —
/// those are LANE_CORE2's territory; this only exercises the pure formatting/layout math).
/// No view-rendering tests here — the conductor eyeballs the sheet at the merge gate.
final class BookTextSummaryDisplayTests: XCTestCase {

    // MARK: - Fixture helpers

    private func perText(
        _ filename: String, title: String? = nil, coveredSeconds: TimeInterval = 0,
        spans: [ClosedRange<TimeInterval>] = [], fileNumbers: [Int] = []
    ) -> BookTextSummary.PerText {
        BookTextSummary.PerText(filename: filename, title: title, coveredSeconds: coveredSeconds,
                                spans: spans, fileNumbers: fileNumbers)
    }

    // MARK: - percentCovered

    func testPercentRoundsToNearestWhole() {
        XCTAssertEqual(BookTextDisplay.percentCovered(covered: 45, total: 100), 45)
        XCTAssertEqual(BookTextDisplay.percentCovered(covered: 44.4, total: 100), 44)
        XCTAssertEqual(BookTextDisplay.percentCovered(covered: 44.5, total: 100), 45)
    }

    func testPercentRealisticMockExample() {
        // mocks/book-text-sheet.html #m2: "covers 45%" of a 4:33:12 book.
        let total: TimeInterval = 4 * 3600 + 33 * 60 + 12
        XCTAssertEqual(BookTextDisplay.percentCovered(covered: total * 0.45, total: total), 45)
    }

    func testPercentZeroTotalNeverDividesByZero() {
        XCTAssertEqual(BookTextDisplay.percentCovered(covered: 50, total: 0), 0)
        XCTAssertEqual(BookTextDisplay.percentCovered(covered: 0, total: 0), 0)
    }

    func testPercentClampsAtHundred() {
        // covered slightly over total (FP overshoot) must never read as "101%".
        XCTAssertEqual(BookTextDisplay.percentCovered(covered: 100.4, total: 100), 100)
    }

    // MARK: - durationText (h/min)

    func testDurationUnderAnHour() {
        XCTAssertEqual(BookTextDisplay.durationText(58 * 60), "58 min")
    }

    func testDurationOverAnHourZeroPadsMinutes() {
        // mocks/book-text-sheet.html #m2's other row example: "1 h 06".
        XCTAssertEqual(BookTextDisplay.durationText(66 * 60), "1 h 06")
    }

    func testDurationZero() {
        XCTAssertEqual(BookTextDisplay.durationText(0), "0 min")
    }

    func testDurationExactlyOneHour() {
        XCTAssertEqual(BookTextDisplay.durationText(3600), "1 h 00")
    }

    func testDurationRoundsToNearestMinute() {
        XCTAssertEqual(BookTextDisplay.durationText(58 * 60 + 40), "59 min")
    }

    func testDurationNegativeSecondsClampsToZero() {
        XCTAssertEqual(BookTextDisplay.durationText(-5), "0 min")
    }

    // MARK: - matchWording / isFullMatch

    func testFullMatchAtToleranceBoundary() {
        let aligned: TimeInterval = 1000
        let covered = aligned * BookTextDisplay.matchTolerance
        XCTAssertTrue(BookTextDisplay.isFullMatch(coveredSeconds: covered, alignedFilesDuration: aligned))
        XCTAssertEqual(BookTextDisplay.matchWording(coveredSeconds: covered, alignedFilesDuration: aligned), "full match")
    }

    func testJustUnderToleranceReadsPartial() {
        let aligned: TimeInterval = 1000
        let covered = aligned * BookTextDisplay.matchTolerance - 1
        XCTAssertFalse(BookTextDisplay.isFullMatch(coveredSeconds: covered, alignedFilesDuration: aligned))
        XCTAssertEqual(BookTextDisplay.matchWording(coveredSeconds: covered, alignedFilesDuration: aligned), "partial")
    }

    func testExactCoverageIsFullMatch() {
        XCTAssertEqual(BookTextDisplay.matchWording(coveredSeconds: 3480, alignedFilesDuration: 3480), "full match")
    }

    func testZeroAlignedDurationIsAlwaysPartial() {
        // Nothing aligned yet must never read as a false "full match" on zero coverage.
        XCTAssertFalse(BookTextDisplay.isFullMatch(coveredSeconds: 0, alignedFilesDuration: 0))
        XCTAssertEqual(BookTextDisplay.matchWording(coveredSeconds: 0, alignedFilesDuration: 0), "partial")
    }

    // MARK: - colorCycleIndex

    func testColorCyclesBetweenAccentAndTan() {
        XCTAssertEqual(BookTextDisplay.colorCycleIndex(0), 0)
        XCTAssertEqual(BookTextDisplay.colorCycleIndex(1), 1)
        XCTAssertEqual(BookTextDisplay.colorCycleIndex(2), 0)
        XCTAssertEqual(BookTextDisplay.colorCycleIndex(3), 1)
        XCTAssertEqual(BookTextDisplay.colorCycleIndex(4), 0)
    }

    // MARK: - barSegments (span → x/width math)

    func testBarSegmentsEmptyPerTextIsOneFullWidthUncoveredSegment() {
        let segments = BookTextDisplay.barSegments(perText: [], bookDuration: 100)
        XCTAssertEqual(segments, [BookTextDisplay.BarSegment(textIndex: nil, startFraction: 0, widthFraction: 1)])
    }

    func testBarSegmentsNonPositiveBookDurationIsEmpty() {
        XCTAssertEqual(BookTextDisplay.barSegments(perText: [perText("a.epub", spans: [0...10])], bookDuration: 0), [])
        XCTAssertEqual(BookTextDisplay.barSegments(perText: [], bookDuration: -5), [])
    }

    func testBarSegmentsSingleSpanWithLeadingAndTrailingGap() {
        // book 0...100, one text covering the middle third only.
        let segments = BookTextDisplay.barSegments(perText: [perText("a.epub", spans: [20...50])], bookDuration: 100)
        XCTAssertEqual(segments, [
            BookTextDisplay.BarSegment(textIndex: nil, startFraction: 0, widthFraction: 0.2),
            BookTextDisplay.BarSegment(textIndex: 0, startFraction: 0.2, widthFraction: 0.3),
            BookTextDisplay.BarSegment(textIndex: nil, startFraction: 0.5, widthFraction: 0.5),
        ])
    }

    func testBarSegmentsTwoTextsBackToBackNoGap() {
        let segments = BookTextDisplay.barSegments(
            perText: [perText("a.epub", spans: [0...40]), perText("b.epub", spans: [40...100])],
            bookDuration: 100
        )
        XCTAssertEqual(segments, [
            BookTextDisplay.BarSegment(textIndex: 0, startFraction: 0, widthFraction: 0.4),
            BookTextDisplay.BarSegment(textIndex: 1, startFraction: 0.4, widthFraction: 0.6),
        ])
    }

    func testBarSegmentsGapBetweenTwoTexts() {
        // an omnibus's un-narrated seam between two attached books.
        let segments = BookTextDisplay.barSegments(
            perText: [perText("a.epub", spans: [0...20]), perText("b.epub", spans: [30...100])],
            bookDuration: 100
        )
        XCTAssertEqual(segments, [
            BookTextDisplay.BarSegment(textIndex: 0, startFraction: 0, widthFraction: 0.2),
            BookTextDisplay.BarSegment(textIndex: nil, startFraction: 0.2, widthFraction: 0.1),
            BookTextDisplay.BarSegment(textIndex: 1, startFraction: 0.3, widthFraction: 0.7),
        ])
    }

    func testBarSegmentsMultipleSpansPerTextAreEachEmitted() {
        // one text aligned in two disjoint stretches (e.g. an interruption the aligner
        // couldn't place) must produce two colored segments, not one merged span.
        let segments = BookTextDisplay.barSegments(
            perText: [perText("a.epub", spans: [0...10, 20...30])],
            bookDuration: 40
        )
        XCTAssertEqual(segments, [
            BookTextDisplay.BarSegment(textIndex: 0, startFraction: 0, widthFraction: 0.25),
            BookTextDisplay.BarSegment(textIndex: nil, startFraction: 0.25, widthFraction: 0.25),
            BookTextDisplay.BarSegment(textIndex: 0, startFraction: 0.5, widthFraction: 0.25),
            BookTextDisplay.BarSegment(textIndex: nil, startFraction: 0.75, widthFraction: 0.25),
        ])
    }

    func testBarSegmentsSpanPastBookDurationIsClamped() {
        let segments = BookTextDisplay.barSegments(perText: [perText("a.epub", spans: [90...150])], bookDuration: 100)
        XCTAssertEqual(segments, [
            BookTextDisplay.BarSegment(textIndex: nil, startFraction: 0, widthFraction: 0.9),
            BookTextDisplay.BarSegment(textIndex: 0, startFraction: 0.9, widthFraction: 0.1),
        ])
    }

    func testBarSegmentsOverlapAcrossTextsClampsRatherThanGoingNegative() {
        // Shouldn't happen given the sentence-level collision rule upstream, but the helper
        // must degrade safely (never a negative width) if it ever does.
        let segments = BookTextDisplay.barSegments(
            perText: [perText("a.epub", spans: [0...50]), perText("b.epub", spans: [10...60])],
            bookDuration: 100
        )
        XCTAssertEqual(segments, [
            BookTextDisplay.BarSegment(textIndex: 0, startFraction: 0, widthFraction: 0.5),
            BookTextDisplay.BarSegment(textIndex: 1, startFraction: 0.5, widthFraction: 0.1),
            BookTextDisplay.BarSegment(textIndex: nil, startFraction: 0.6, widthFraction: 0.4),
        ])
        for seg in segments { XCTAssertGreaterThanOrEqual(seg.widthFraction, 0) }
    }

    func testBarSegmentsDeterministic() {
        let input = [perText("a.epub", spans: [0...20]), perText("b.epub", spans: [30...100])]
        let first = BookTextDisplay.barSegments(perText: input, bookDuration: 100)
        let second = BookTextDisplay.barSegments(perText: input, bookDuration: 100)
        XCTAssertEqual(first, second)
    }
}
