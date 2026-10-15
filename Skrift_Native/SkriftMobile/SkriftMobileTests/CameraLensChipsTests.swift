import XCTest
@testable import SkriftMobile

/// Q465: the zoom chips follow what the device can really do.
final class CameraLensChipsTests: XCTestCase {
    /// Display range of a triple camera: videoZoomFactor 1...20 with base 2 -> 0.5...5 (capped).
    private let virtualRange = CameraZoom.range(deviceMin: 1 / 2, deviceMax: 10)
    private let wideRange = CameraZoom.range(deviceMin: 1, deviceMax: 10)

    func testTripleCameraShowsHalfOneTwo() {
        XCTAssertEqual(CameraLens.chips(for: .tripleBack, displayRange: virtualRange), [0.5, 1, 2])
    }

    func testDualWideShowsHalfOneTwo() {
        XCTAssertEqual(CameraLens.chips(for: .dualWideBack, displayRange: virtualRange), [0.5, 1, 2])
    }

    func testPlainWideHasNoHalfChip() {
        XCTAssertEqual(CameraLens.chips(for: .wideBack, displayRange: wideRange), [1, 2])
    }

    func testFrontShowsNoChips() {
        XCTAssertEqual(CameraLens.chips(for: .front, displayRange: 1...5), [])
    }

    func testHalfChipNeedsTheRangeToReachIt() {
        // A virtual device whose display range does not go below 1 must not advertise .5x.
        XCTAssertEqual(CameraLens.chips(for: .tripleBack, displayRange: 1...5), [1, 2])
    }

    func testTwoXOnlyWhenRangeReachesIt() {
        XCTAssertEqual(CameraLens.chips(for: .wideBack, displayRange: 1...1.5), [1])
    }

    func testBaseFactorMapsDisplayOneToTheWideLens() {
        XCTAssertEqual(CameraLens.baseFactor(hasUltraWide: true, firstSwitchOver: 2), 2)
        XCTAssertEqual(CameraLens.baseFactor(hasUltraWide: true, firstSwitchOver: nil), 1)
        XCTAssertEqual(CameraLens.baseFactor(hasUltraWide: false, firstSwitchOver: 2), 1)
    }
}
