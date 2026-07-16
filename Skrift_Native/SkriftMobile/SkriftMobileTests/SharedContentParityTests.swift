import XCTest
@testable import SkriftMobile

/// C3 capture-contract goldens for the `SharedContent` wire struct (the blob in
/// `Memo.sharedContentData`, passed verbatim into the Mac's metadata envelope by
/// `MemoCloudIngest`). Pins the JSON key set + `type` raw values so the shared
/// type can never drift from bytes phones have already written. The desktop suite
/// carries the same fixture (SharedContentParityTests) against its envelope decode.
final class SharedContentParityTests: XCTestCase {

    /// Every C3 field populated — the full wire surface.
    static let goldenJSON = """
        {"fileName":"Scan.pdf","filePath":"file_7.pdf","mimeType":"application/pdf",\
        "text":"INVOICE 7788","type":"url","url":"https://example.com/a",\
        "urlDescription":"A description","urlThumbnailUrl":"https://example.com/t.jpg",\
        "urlTitle":"Example Page"}
        """

    func testGoldenDecodesAllFields() throws {
        let sc = try JSONDecoder().decode(SharedContent.self, from: Data(Self.goldenJSON.utf8))
        XCTAssertEqual(sc.type, .url)
        XCTAssertEqual(sc.url, "https://example.com/a")
        XCTAssertEqual(sc.urlTitle, "Example Page")
        XCTAssertEqual(sc.urlDescription, "A description")
        XCTAssertEqual(sc.urlThumbnailUrl, "https://example.com/t.jpg")
        XCTAssertEqual(sc.text, "INVOICE 7788")
        XCTAssertEqual(sc.filePath, "file_7.pdf")
        XCTAssertEqual(sc.fileName, "Scan.pdf")
        XCTAssertEqual(sc.mimeType, "application/pdf")
    }

    func testEncodeKeepsTheContractKeys() throws {
        let sc = try JSONDecoder().decode(SharedContent.self, from: Data(Self.goldenJSON.utf8))
        let obj = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: JSONEncoder().encode(sc)) as? [String: Any])
        XCTAssertEqual(obj.keys.sorted(),
                       ["fileName", "filePath", "mimeType", "text", "type", "url",
                        "urlDescription", "urlThumbnailUrl", "urlTitle"],
                       "wire keys renamed or dropped — the C3 contract broke")
        XCTAssertEqual(obj["type"] as? String, "url")
    }

    func testFullRoundTripIsLossless() throws {
        let sc = try JSONDecoder().decode(SharedContent.self, from: Data(Self.goldenJSON.utf8))
        let back = try JSONDecoder().decode(SharedContent.self, from: JSONEncoder().encode(sc))
        XCTAssertEqual(sc, back)
    }

    func testTypeRawValuesAreTheContract() {
        XCTAssertEqual(ShareContentType.url.rawValue, "url")
        XCTAssertEqual(ShareContentType.image.rawValue, "image")
        XCTAssertEqual(ShareContentType.text.rawValue, "text")
        XCTAssertEqual(ShareContentType.file.rawValue, "file")
    }
}
