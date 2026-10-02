import XCTest
import Foundation

/// Q138 (P39): `SourceKind.of` on the shapes the PHONE really writes, not the wrapped shape the
/// old `SourceTaxonomyTests` seeded. `CaptureInboxDrainer` writes the bare `SharedContent` into
/// `Memo.sharedContentData` and NO metadata wrapper; a phone video encodes `MemoMetadata`
/// (`sourceType`, no CodingKeys). Same class name in the mobile suite (`plan/mtest.sh`).
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

    func testPhoneVideoReadsMemoMetadataSourceType() throws {
        let m = Memo(audioFilename: "v.m4a", recordedAt: Date(), transcript: "words", transcriptStatus: .done)
        m.metadataData = try JSONEncoder().encode(MemoMetadata(sourceType: MemoMetadata.Source.video))
        XCTAssertEqual(SourceKind.of(m), .video)
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

#if canImport(AppKit)
    /// The Mac side: an UNRATED phone capture / video projects with the right row kind and the
    /// pane's capture branch (`CaptureBanner` needs `.capture` + a decodable shared blob).
    func testMacProjectionOfAPhoneCaptureAndVideo() throws {
        let cap = try capture(SharedContent(type: .url, url: "https://example.com"))
        let pf = MemoNoteProjection.file(for: cap)
        XCTAssertEqual(pf.sourceType, .capture)
        XCTAssertEqual(pf.sourceDescriptor.glyph, SourceKind.captureURL.glyph)
        XCTAssertEqual(pf.sharedContentType, "url")

        let vid = Memo(audioFilename: "v.m4a", recordedAt: Date(), transcript: "w", transcriptStatus: .done)
        vid.metadataData = try JSONEncoder().encode(MemoMetadata(sourceType: MemoMetadata.Source.video))
        let vpf = MemoNoteProjection.file(for: vid)
        XCTAssertEqual(vpf.sourceType, .audio)
        XCTAssertEqual(vpf.sourceDescriptor.glyph, SourceKind.video.glyph)
    }
#endif
}
