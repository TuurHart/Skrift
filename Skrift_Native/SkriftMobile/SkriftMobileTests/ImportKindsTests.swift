import XCTest
import UniformTypeIdentifiers
@testable import SkriftMobile

/// C238 / C199 / D19: the same file name resolves to the same kind on the phone and the Mac.
/// The Mac twin (`SkriftDesktopTests/ImportKindsTests.swift`) carries the SAME table against
/// `IngestService.importKind(of:)`.
@MainActor
final class ImportKindsTests: XCTestCase {
    static let table: [(String, ImportKinds.Kind?)] = [
        ("memo.m4a", .audio), ("a.MP3", .audio), ("b.wav", .audio), ("c.aac", .audio),
        ("d.caf", .audio), ("e.aiff", .audio), ("f.aif", .audio), ("g.opus", .audio),
        ("h.ogg", .audio), ("i.oga", .audio), ("j.flac", .audio),
        ("v.mov", .video), ("w.MP4", .video), ("x.m4v", .video), ("y.webm", .video), ("z.mkv", .video),
        ("p.jpg", .image), ("p.JPEG", .image), ("p.png", .image), ("p.heic", .image),
        ("n.md", .text), ("n.markdown", .text), ("n.txt", .text),
        ("doc.pdf", .document),
        ("book.epub", .book), ("book.m4b", .book), ("share.skriftbook", .book),
        ("archive.zip", nil), ("noextension", nil),
    ]

    func testSameNamesSameKind() {
        for (name, kind) in Self.table {
            XCTAssertEqual(AppURLHandler.importKind(of: URL(fileURLWithPath: "/tmp/\(name)")), kind, name)
        }
    }

    func testOpenInAcceptsWhatTheShareSheetAccepts() {
        // C199: ogg / oga were share-sheet-only; flac / aif were Open-in-only.
        for ext in ["ogg", "oga", "flac", "aif", "opus"] {
            XCTAssertEqual(ImportKinds.kind(forExtension: ext), .audio, ext)
        }
        XCTAssertEqual(MemoSaver.videoExtensions, ImportKinds.videoExtensions)
    }

    func testFilesPickerOffersPdfTextAndImages() {
        let types = ImportKinds.allowedContentTypes()
        XCTAssertTrue(types.contains(.audio) && types.contains(.movie) && types.contains(.image)
                      && types.contains(.pdf) && types.contains(.plainText))
    }

    func testMissingFileIsNotImportedAsCapture() {
        XCTAssertFalse(AppURLHandler.importAsCapture(URL(fileURLWithPath: "/tmp/definitely-not-here-\(UUID()).pdf")))
        XCTAssertFalse(AppURLHandler.importAsCapture(URL(fileURLWithPath: "/tmp/clip.m4a")))
    }
}
