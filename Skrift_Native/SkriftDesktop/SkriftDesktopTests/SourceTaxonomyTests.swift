import XCTest
import Foundation

/// The shared source taxonomy (Shared/Pipeline/SourceTaxonomy.swift) — ONE copy
/// of every source kind's glyph + label, and the Memo-side derivation. Same
/// file in both suites (mobile adds the @testable import).
final class SourceTaxonomyTests: XCTestCase {

    private func memo(audioFilename: String = "m.m4a") -> Memo {
        Memo(audioFilename: audioFilename, recordedAt: Date(),
             transcript: "words", transcriptStatus: .done)
    }

    func testAudiobookQuoteBeatsEverything() throws {
        let m = memo()
        m.metadataData = try JSONEncoder().encode(MemoMetadata(bookTitle: "The Trouble with Goats"))
        XCTAssertEqual(SourceKind.of(m), .audiobookQuote)
        XCTAssertEqual(SourceKind.audiobookQuote.glyph, "book.closed.fill")
    }

    func testVideo() throws {
        let m = memo()
        m.metadataData = try JSONSerialization.data(withJSONObject: ["mediaSource": "video"])
        XCTAssertEqual(SourceKind.of(m), .video)
        XCTAssertEqual(SourceKind.video.glyph, "video.fill")
    }

    func testCaptureSubtypes() throws {
        let m = memo()
        m.metadataData = try JSONSerialization.data(withJSONObject:
            ["sharedContent": ["type": "url", "url": "https://example.com"]])
        XCTAssertEqual(SourceKind.of(m), .captureURL)
        XCTAssertEqual(SourceKind.captureURL.glyph, "link")
    }

    func testFallsBackToVoiceOrNote() {
        XCTAssertEqual(SourceKind.of(memo()), .voiceMemo)
        XCTAssertEqual(SourceKind.of(memo(audioFilename: "")), .appleNote)
    }

    /// Every kind renders a REAL SF Symbol — a typo'd name draws nothing
    /// (the invisible-icon failure class from the global self-check list).
    func testEveryGlyphIsAValidSFSymbol() {
        let kinds: [SourceKind] = [.audiobookQuote, .video, .captureURL, .captureImage,
                                   .captureText, .captureFile, .captureOther, .appleNote, .voiceMemo]
        for kind in kinds {
            #if canImport(AppKit)
            XCTAssertNotNil(NSImage(systemSymbolName: kind.glyph, accessibilityDescription: nil),
                            "\(kind) → '\(kind.glyph)' is not a real SF Symbol")
            #elseif canImport(UIKit)
            XCTAssertNotNil(UIImage(systemName: kind.glyph),
                            "\(kind) → '\(kind.glyph)' is not a real SF Symbol")
            #endif
            XCTAssertFalse(kind.label.isEmpty)
        }
    }
}
#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif
