import XCTest
@testable import SkriftMobile

/// Q456 / C221: pinch zoom must not compound. Scale is relative to gesture start.
final class CaptureCameraZoomTests: XCTestCase {
    private let range: ClosedRange<CGFloat> = 1...5

    func testPinchIsStartTimesScale() {
        XCTAssertEqual(CameraZoom.pinched(start: 2, scale: 1.5, range: range), 3, accuracy: 0.0001)
    }

    func testRepeatedChangesFromSameStartDoNotCompound() {
        // A real pinch fires onChanged many times with a slowly growing scale; every
        // call uses the SAME start. The result tracks the scale, never its running product.
        let start: CGFloat = 1
        var last: CGFloat = 0
        for scale in stride(from: CGFloat(1.0), through: 1.4, by: 0.05) {
            last = CameraZoom.pinched(start: start, scale: scale, range: range)
        }
        XCTAssertEqual(last, 1.4, accuracy: 0.0001)
    }

    func testClampsToDeviceRange() {
        XCTAssertEqual(CameraZoom.pinched(start: 2, scale: 10, range: range), 5)
        XCTAssertEqual(CameraZoom.pinched(start: 2, scale: 0.1, range: range), 1)
    }

    func testRangeCapsAtUICeilingAndKeepsDeviceMin() {
        let r = CameraZoom.range(deviceMin: 0.5, deviceMax: 123)
        XCTAssertEqual(r.lowerBound, 0.5)
        XCTAssertEqual(r.upperBound, CameraZoom.uiCeiling)
        let small = CameraZoom.range(deviceMin: 1, deviceMax: 3)
        XCTAssertEqual(small.upperBound, 3)
    }
}
