import XCTest
@testable import SkriftMobile

/// Q352 (Q6 mock): the Library source kind rides inside the Audiobook blob (no schema change),
/// old records read as books, and the empty tab lists four doors with only the built ones shown.
final class LibraryShelfTests: XCTestCase {

    private func book() -> Audiobook {
        Audiobook(audioFilename: "a.m4b", title: "T", author: "A", duration: 100)
    }

    func testKindRoundTripsThroughTheBlob() throws {
        for kind in LibrarySourceKind.allCases {
            var b = book()
            b.kind = kind
            let data = try JSONEncoder().encode(b.sanitizedForSync())
            let back = try JSONDecoder().decode(Audiobook.self, from: data)
            XCTAssertEqual(back.kind, kind)
            XCTAssertEqual(back.sourceKind, kind)
        }
    }

    func testNilKindDecodesAsBook() throws {
        let data = try JSONEncoder().encode(book())
        // Strip the key entirely: a record written before Q352.
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        json.removeValue(forKey: "kind")
        let old = try JSONSerialization.data(withJSONObject: json)
        let back = try JSONDecoder().decode(Audiobook.self, from: old)
        XCTAssertNil(back.kind)
        XCTAssertEqual(back.sourceKind, .book)
    }

    func testNilKindIsNotWrittenSoOldBuildsSeeTheSameBlob() throws {
        let data = try JSONEncoder().encode(book())
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertNil(json["kind"])
    }

    func testUnknownKindFromANewerBuildDecodesAsBook() throws {
        let data = try JSONEncoder().encode(book())
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        json["kind"] = "talk"
        let blob = try JSONSerialization.data(withJSONObject: json)
        let back = try JSONDecoder().decode(Audiobook.self, from: blob)
        XCTAssertEqual(back.sourceKind, .book)
    }

    func testEmptyStateListsFourDoors() {
        XCTAssertEqual(LibraryDoor.all.map(\.title),
                       ["Audiobook", "Podcast or episode", "ePub or PDF", "Article"])
        XCTAssertEqual(LibraryDoor.all.map(\.kind), [.book, .episode, .pdf, .article])
        XCTAssertEqual(LibraryDoor.heading, "Add your first book, podcast, article or PDF")
    }

    func testOnlyBuiltDoorsAreShown() {
        XCTAssertTrue(LibraryDoor.visible.allSatisfy(\.isBuilt))
        XCTAssertTrue(LibraryDoor.visible.contains(.audiobook))
        XCTAssertTrue(LibraryDoor.visible.contains(.podcast))   // built in Q353 (Tuur approved Q371)
        XCTAssertTrue(LibraryDoor.visible.contains(.epubOrPDF)) // built in Q354
    }
}
