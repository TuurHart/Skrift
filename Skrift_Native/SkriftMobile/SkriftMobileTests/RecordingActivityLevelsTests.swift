import XCTest
@testable import SkriftMobile

/// Q339: the Dynamic Island waveform sat still because the widget drew it with a
/// `TimelineView(.animation)`, which a Live Activity never ticks. The bars are now
/// `ContentState.levels`, pushed by the app. These pin the state the island reads.
final class RecordingActivityLevelsTests: XCTestCase {
    typealias State = RecordingActivityAttributes.ContentState

    func testEmptySamplesGiveNoBars() {
        XCTAssertEqual(RecordingActivityManager.islandBars([]), [])
    }

    func testBarsAreFiveAndTakeThePeakOfEachSlice() {
        // 15 samples -> 5 slices of 3; each bar is its slice's peak, oldest left.
        let samples: [Float] = [0.1, 0.2, 0.3,  0.0, 0.9, 0.1,  0.4, 0.4, 0.4,  0.0, 0.0, 0.0,  0.5, 0.2, 1.0]
        XCTAssertEqual(RecordingActivityManager.islandBars(samples), [0.3, 0.9, 0.4, 0.0, 1.0])
    }

    func testFewerSamplesThanBarsStillFillEveryBar() {
        let bars = RecordingActivityManager.islandBars([0.2, 0.8])
        XCTAssertEqual(bars.count, State.barCount)
        XCTAssertEqual(bars.first, 0.2)
        XCTAssertEqual(bars.last, 0.8)
    }

    func testBarsAreClampedToUnitRange() {
        let bars = RecordingActivityManager.islandBars([-1, 3, 0.5, 0.5, 0.5])
        XCTAssertEqual(bars, [0.0, 1.0, 0.5, 0.5, 0.5])
    }

    func testLevelsChangeTheState() {
        let t = Date(timeIntervalSince1970: 1000)
        let a = State(status: .recording, caption: "", startedAt: t, levels: [0.1, 0.2, 0.3, 0.4, 0.5])
        let b = State(status: .recording, caption: "", startedAt: t, levels: [0.5, 0.4, 0.3, 0.2, 0.1])
        // ActivityKit only redraws when the pushed content differs.
        XCTAssertNotEqual(a, b)
    }

    func testLevelsSurviveEncodeDecode() throws {
        let s = State(status: .recording, caption: "hi", startedAt: Date(timeIntervalSince1970: 5),
                      levels: [0.25, 0.5, 0.75, 1, 0])
        let back = try JSONDecoder().decode(State.self, from: JSONEncoder().encode(s))
        XCTAssertEqual(back, s)
    }

    func testStateWithoutLevelsStillDecodes() throws {
        let json = #"{"status":"paused","caption":"x","startedAt":10,"pausedAt":12}"#
        let s = try JSONDecoder().decode(State.self, from: Data(json.utf8))
        XCTAssertEqual(s.levels, [])
        XCTAssertEqual(s.status, .paused)
    }
}
