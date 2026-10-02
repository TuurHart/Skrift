import XCTest
@testable import SkriftMobile
import Foundation

/// Q138 (P39): `SourceKind.of` on the shapes the PHONE really writes, not the wrapped shape the
/// old `SourceTaxonomyTests` seeded. `CaptureInboxDrainer` writes the bare `SharedContent` into
/// `Memo.sharedContentData` and NO metadata wrapper; a phone video encodes `MemoMetadata`
/// (`sourceType`, no CodingKeys). Same class name in the desktop suite.
final class SourceKindRealShapeTests: XCTestCase {

    private func capture(_ sc: SharedContent) throws -> Memo {
        let m = Memo(audioFilename: "", recordedAt: Date(), transcript: nil, transcriptStatus: .done)
        m.sharedContentData = try JSONEncoder().encode(sc)   // exactly what the drainer stores
        return m
    }

    func testPhoneCaptureReadsFromTheBareBlob() throws {
        XCTAssertEqual(SourceKind.of(try capture(SharedContent(type: .url, url: "https://example.com"))), .captureURL)
        XCTAssertEqual(SourceKind.of(try capture(SharedContent(type: .text, text: "hi"))), .captureText)
        XCTAssertEqual(SourceKind.of(try capture(SharedContent(type: .image))), .captureImage)
        XCTAssertEqual(SourceKind.of(try capture(SharedContent(type: .file, fileName: "a.pdf"))), .captureFile)
    }

    func testPhoneHelpersAgreeWithTheClassifier() throws {
        let m = try capture(SharedContent(type: .text, text: "hi"))
        XCTAssertTrue(m.isShareCapture)
        XCTAssertEqual(m.shareCaptureGlyph, SourceKind.captureText.glyph)
    }

    func testPhoneVideoReadsMemoMetadataSourceType() throws {
        let m = Memo(audioFilename: "v.m4a", recordedAt: Date(), transcript: "words", transcriptStatus: .done)
        m.metadataData = try JSONEncoder().encode(MemoMetadata(sourceType: MemoMetadata.Source.video))
        XCTAssertEqual(SourceKind.of(m), .video)
        XCTAssertTrue(m.isVideoImport)
    }

    func testMacVideoMarkerStillReads() throws {
        let m = Memo(audioFilename: "v.m4a", recordedAt: Date(), transcript: "words", transcriptStatus: .done)
        m.metadataData = try JSONSerialization.data(withJSONObject: ["mediaSource": "video"])
        XCTAssertEqual(SourceKind.of(m), .video)
    }

    func testUnknownCaptureTypeIsNotACapture() {
        let m = Memo(audioFilename: "", recordedAt: Date(), transcript: nil, transcriptStatus: .done)
        m.sharedContentData = Data(#"{"type":"hologram"}"#.utf8)
        XCTAssertNil(m.sharedContent)
        XCTAssertEqual(SourceKind.of(m), .appleNote)
    }
}
