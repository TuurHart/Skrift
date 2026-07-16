import XCTest
import MapKit

/// `PlaceCluster.fitRegion` — the pure fit-all math behind the rail mini-map shot
/// and the full map's fit-all entry (mocks/review-minimap.html #m1).
final class PlaceClusterTests: XCTestCase {

    private func cluster(_ id: String, _ lat: Double, _ lon: Double) -> PlaceCluster {
        PlaceCluster(id: id, name: id,
                     coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon),
                     memos: [])
    }

    func testFitRegionEmptyIsNil() {
        XCTAssertNil(PlaceCluster.fitRegion(for: []))
    }

    func testFitRegionSinglePinGetsMinimumSpan() throws {
        let r = try XCTUnwrap(PlaceCluster.fitRegion(for: [cluster("a", 38.7, -9.2)]))
        XCTAssertEqual(r.center.latitude, 38.7, accuracy: 0.0001)
        XCTAssertEqual(r.center.longitude, -9.2, accuracy: 0.0001)
        XCTAssertEqual(r.span.latitudeDelta, 0.05, accuracy: 0.0001, "min span — never street-level")
        XCTAssertEqual(r.span.longitudeDelta, 0.05, accuracy: 0.0001)
    }

    func testFitRegionContainsAllPinsWithPadding() throws {
        // Lisbon-ish + Leiden-ish — the real corpus shape.
        let r = try XCTUnwrap(PlaceCluster.fitRegion(for: [
            cluster("barcarena", 38.73, -9.28),
            cluster("leiden", 52.16, 4.49),
        ]))
        XCTAssertEqual(r.center.latitude, (38.73 + 52.16) / 2, accuracy: 0.0001)
        XCTAssertEqual(r.span.latitudeDelta, (52.16 - 38.73) * 1.35, accuracy: 0.0001, "padded bounding box")
        // Both pins inside the region.
        for lat in [38.73, 52.16] {
            XCTAssertTrue(abs(lat - r.center.latitude) <= r.span.latitudeDelta / 2)
        }
        for lon in [-9.28, 4.49] {
            XCTAssertTrue(abs(lon - r.center.longitude) <= r.span.longitudeDelta / 2)
        }
    }
}
