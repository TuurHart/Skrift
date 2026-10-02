import XCTest
import UniformTypeIdentifiers

/// C238 / C199 / D19: the same file name resolves to the same kind on the Mac and the phone.
/// The phone twin of this class (`SkriftMobileTests/ImportKindsTests.swift`) carries the SAME
/// table against `AppURLHandler.importKind(of:)`.
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
            XCTAssertEqual(IngestService.importKind(of: URL(fileURLWithPath: "/tmp/\(name)")), kind, name)
        }
    }

    func testMacAcceptsEveryAudioTheShareSheetDoes() {
        // The share extension's old list added ogg/oga; the Mac's old list had no flac/aif/ogg/oga.
        for ext in ["flac", "aif", "ogg", "oga", "opus", "m4a"] {
            XCTAssertTrue(IngestService.supportedAudio.contains(ext), ext)
        }
        XCTAssertTrue(IngestService.supportedVideo.isSuperset(of: ["webm", "mkv", "mov", "mp4"]))
    }

    func testNoExtensionBelongsToTwoKinds() {
        var seen: [String: ImportKinds.Kind] = [:]
        for kind in ImportKinds.Kind.allCases {
            for ext in ImportKinds.extensions(of: kind) {
                XCTAssertNil(seen[ext], "\(ext) is in two kinds")
                seen[ext] = kind
            }
        }
    }

    func testPickerTypesCoverTheNoteKindsAndNotBooks() {
        let types = ImportKinds.allowedContentTypes()
        XCTAssertTrue(types.contains(.audio) && types.contains(.movie) && types.contains(.image)
                      && types.contains(.pdf) && types.contains(.plainText))
        XCTAssertFalse(types.contains { $0.preferredFilenameExtension == "epub" })
    }
}
