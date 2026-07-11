import XCTest
@testable import SkriftMobile

/// D6: Apple/Google Maps share links → place name + pin (pure parser).
final class PlaceLinkTests: XCTestCase {

    func testAppleMapsLlAndQ() throws {
        let p = try XCTUnwrap(PlaceLink.parse(
            "https://maps.apple.com/?ll=38.7223,-9.1393&q=Hotel%20Du%20Vin&lsp=9902"))
        XCTAssertEqual(p.name, "Hotel Du Vin")
        XCTAssertEqual(p.latitude, 38.7223, accuracy: 0.0001)
        XCTAssertEqual(p.longitude, -9.1393, accuracy: 0.0001)
    }

    func testAppleMapsPlaceCoordinateForm() throws {
        let p = try XCTUnwrap(PlaceLink.parse(
            "https://maps.apple.com/place?coordinate=38.71,-9.14&name=Time+Out+Market"))
        XCTAssertEqual(p.latitude, 38.71, accuracy: 0.001)
        XCTAssertNotNil(p.name)
    }

    func testAppleMapsQAsBareCoordsGivesNoName() throws {
        let p = try XCTUnwrap(PlaceLink.parse("https://maps.apple.com/?ll=38.7,-9.1&q=38.7,-9.1"))
        XCTAssertNil(p.name, "a coords-only q param is not a place name")
    }

    func testGoogleMapsPlacePath() throws {
        let p = try XCTUnwrap(PlaceLink.parse(
            "https://www.google.com/maps/place/Pasteis+de+Belem/@38.6976,-9.2033,17z/data=xyz"))
        XCTAssertEqual(p.name, "Pasteis de Belem")
        XCTAssertEqual(p.latitude, 38.6976, accuracy: 0.0001)
        XCTAssertEqual(p.longitude, -9.2033, accuracy: 0.0001)
    }

    func testGoogleMapsQueryCoords() throws {
        let p = try XCTUnwrap(PlaceLink.parse("https://maps.google.com/?q=38.70,-9.13"))
        XCTAssertNil(p.name)
        XCTAssertEqual(p.latitude, 38.70, accuracy: 0.001)
    }

    func testNonMapsAndOpaqueLinksAreNil() {
        XCTAssertNil(PlaceLink.parse("https://example.com/?ll=38.7,-9.1"))
        XCTAssertNil(PlaceLink.parse("https://maps.app.goo.gl/AbCdEf123"), "short link is opaque without a fetch")
        XCTAssertNil(PlaceLink.parse("https://maps.apple.com/?q=Lisbon"), "no coordinates → no pin")
        XCTAssertNil(PlaceLink.parse("not a url at all"))
        XCTAssertNil(PlaceLink.parse("https://maps.apple.com/?ll=999,-9.1&q=Broken"), "lat out of range")
    }
}
