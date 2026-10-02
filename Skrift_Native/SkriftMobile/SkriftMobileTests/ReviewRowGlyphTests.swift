import XCTest
@testable import SkriftMobile

/// Q169 (C78/C115): the Review note row leads with the source glyph (never a hard-coded mic),
/// and the Way-out entry facts (glyph, count, unread dot) are one shared rule.
final class ReviewRowGlyphTests: XCTestCase {

    private func memo(audio: String = "a.m4a", meta: String? = nil) -> Memo {
        Memo(audioFilename: audio, recordedAt: Date(), metadataData: meta.map { Data($0.utf8) })
    }

    func testVoiceMemoRowUsesSourceGlyph() {
        XCTAssertEqual(SourceKind.rowGlyph(for: memo(), hidden: false), SourceKind.voiceMemo.glyph)
    }

    func testNoAudioNoteIsNotAMic() {
        let m = memo(audio: "")
        XCTAssertEqual(SourceKind.rowGlyph(for: m, hidden: false), SourceKind.appleNote.glyph)
        XCTAssertNotEqual(SourceKind.rowGlyph(for: m, hidden: false), "mic")
    }

    func testTypedNoteGlyph() {
        let m = memo(audio: "", meta: #"{"mediaSource":"typed"}"#)
        XCTAssertEqual(SourceKind.rowGlyph(for: m, hidden: false), SourceKind.typedNote.glyph)
    }

    func testHiddenNoteShowsLock() {
        XCTAssertEqual(SourceKind.rowGlyph(for: memo(), hidden: true), "lock.fill")
    }

    func testWayOutEntryFacts() {
        XCTAssertEqual(WayOut.entryGlyph, "leaf")
        XCTAssertEqual(WayOut.entryCount(fading: 3, deleted: 2), 5)
    }
}
