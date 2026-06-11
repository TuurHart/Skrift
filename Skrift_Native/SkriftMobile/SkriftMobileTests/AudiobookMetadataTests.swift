import XCTest
@testable import SkriftMobile

/// Tag-parsing fallbacks for audiobook import: the editable confirm sheet
/// triggers ONLY when a tag is missing, pre-filled from these defaults.
final class AudiobookMetadataTests: XCTestCase {

    func testCompleteTagsNeedNoConfirmation() {
        let r = AudiobookMetadataDefaults.resolve(
            title: "Antifragile", author: "Nassim Nicholas Taleb", filename: "anything.m4b"
        )
        XCTAssertEqual(r.title, "Antifragile")
        XCTAssertEqual(r.author, "Nassim Nicholas Taleb")
        XCTAssertFalse(r.needsConfirmation)
    }

    func testMissingAuthorNeedsConfirmation() {
        let r = AudiobookMetadataDefaults.resolve(
            title: "Antifragile", author: nil, filename: "antifragile.m4b"
        )
        XCTAssertEqual(r.title, "Antifragile")
        XCTAssertEqual(r.author, "")
        XCTAssertTrue(r.needsConfirmation)
    }

    func testMissingTitleFallsBackToFilename() {
        let r = AudiobookMetadataDefaults.resolve(
            title: nil, author: "David Deutsch", filename: "The_Beginning_of_Infinity.m4b"
        )
        XCTAssertEqual(r.title, "The Beginning of Infinity")
        XCTAssertTrue(r.needsConfirmation)
    }

    func testWhitespaceOnlyTagsCountAsMissing() {
        let r = AudiobookMetadataDefaults.resolve(title: "  ", author: "\n", filename: "book.mp3")
        XCTAssertEqual(r.title, "book")
        XCTAssertEqual(r.author, "")
        XCTAssertTrue(r.needsConfirmation)
    }

    func testFilenameTitleCollapsesSeparators() {
        XCTAssertEqual(
            AudiobookMetadataDefaults.filenameTitle("My__Great   Book .m4a"),
            "My Great Book"
        )
        XCTAssertEqual(AudiobookMetadataDefaults.filenameTitle("___.m4b"), "Untitled audiobook")
    }
}
