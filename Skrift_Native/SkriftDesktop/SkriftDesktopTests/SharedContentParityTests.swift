import XCTest

/// C3 capture-contract goldens for the desktop `SharedContent` envelope decode —
/// the SAME inner fixture as the mobile suite (SharedContentParityTests), wrapped
/// the way `MemoCloudIngest` embeds it in the metadata JSON. Pins the decode path
/// so the SharedKit unification can't change what synced captures decode to.
final class SharedContentParityTests: XCTestCase {

    /// Every C3 field populated — the full wire surface (superset; extra keys the
    /// desktop doesn't read must be tolerated, they're the phone-only fields).
    static let goldenInner = """
        {"fileName":"Scan.pdf","filePath":"file_7.pdf","mimeType":"application/pdf",\
        "text":"INVOICE 7788","type":"url","url":"https://example.com/a",\
        "urlDescription":"A description","urlThumbnailUrl":"https://example.com/t.jpg",\
        "urlTitle":"Example Page"}
        """

    private func envelope(key: String = "sharedContent") -> Data {
        Data("{\"recordedAt\":\"2026-07-16T08:00:00.000Z\",\"\(key)\":\(Self.goldenInner)}".utf8)
    }

    func testEnvelopeDecodesCamelCase() throws {
        let sc = try XCTUnwrap(SharedContent.decode(from: envelope()))
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

    func testSnakeCaseKeyIsNotTheContract() {
        // Golden finding (2026-07-16): the snake_case "fallback" in the old desktop
        // decoder was DEAD code — the Codable wrapper succeeds (sharedContent: nil) on
        // any JSON object, so `shared_content` never decoded. No producer exists (the
        // demo seeds died with the RN era). camelCase is the C3 contract; the shared
        // decoder carries no fallback.
        XCTAssertNil(SharedContent.decode(from: envelope(key: "shared_content")))
    }

    func testUnknownTypeYieldsNil() {
        // Strict enum: a type outside the C3 contract decodes to nil rather than a
        // junk-typed record (better no info than bad info). Adding a capture type =
        // extending the ONE shared ShareContentType — both apps move together.
        let data = Data(#"{"sharedContent":{"type":"hologram","urlTitle":"X"}}"#.utf8)
        XCTAssertNil(SharedContent.decode(from: data))
    }

    func testAbsentOrJunkYieldsNil() {
        XCTAssertNil(SharedContent.decode(from: Data(#"{"recordedAt":"x"}"#.utf8)))
        XCTAssertNil(SharedContent.decode(from: Data("junk".utf8)))
        XCTAssertNil(SharedContent.decode(from: nil))
    }
}
