import XCTest
import Foundation
@testable import SkriftMobile

/// Q121 (C115/C240): the ONE clock label and the ONE playback-speed list, on both apps.
/// The same class runs in SkriftDesktopTests against the same Shared/UI files.
final class DurationFormatTests: XCTestCase {

    func testUnderAnHourIsMinutesSeconds() {
        XCTAssertEqual(DurationFormat.label(seconds: 0), "0:00")
        XCTAssertEqual(DurationFormat.label(seconds: 7), "0:07")
        XCTAssertEqual(DurationFormat.label(seconds: 187), "3:07")
        XCTAssertEqual(DurationFormat.label(seconds: 3599), "59:59")
    }

    func testAnHourOrMoreIsHoursMinutesSeconds() {
        XCTAssertEqual(DurationFormat.label(seconds: 3600), "1:00:00")
        // 125:33 as m:ss was the bug.
        XCTAssertEqual(DurationFormat.label(seconds: 125 * 60 + 33), "2:05:33")
    }

    func testBadInputReadsZero() {
        XCTAssertEqual(DurationFormat.label(seconds: .nan), "0:00")
        XCTAssertEqual(DurationFormat.label(seconds: .infinity), "0:00")
        XCTAssertEqual(DurationFormat.label(seconds: -5), "0:00")
    }

    func testRatesAreTheMacList() {
        XCTAssertEqual(PlaybackRates.steps, [0.75, 1, 1.25, 1.5, 2])
    }

    func testRateCycleWrapsAndRecovers() {
        XCTAssertEqual(PlaybackRates.next(after: 1), 1.25)
        XCTAssertEqual(PlaybackRates.next(after: 2), 0.75)
        XCTAssertEqual(PlaybackRates.next(after: 3), 1, "a rate off the list restarts at 1x")
    }

    func testRateLabelKnowsEveryStep() {
        XCTAssertEqual(PlaybackRates.steps.map(PlaybackRates.label),
                       ["0.75×", "1×", "1.25×", "1.5×", "2×"])
    }

    /// The phone's own formatter twins now route through the shared one.
    func testPhoneLabelsRouteThroughSharedFormat() {
        XCTAssertEqual(NoteCardBuilder.duration(seconds: 7533), DurationFormat.label(seconds: 7533))
    }
}
