import XCTest
import Foundation

/// Q380: the row draws no chips any more (D194), so the source / length parity the old chip
/// goldens held now lives on the one marker the row DOES draw: line 3's `media`
/// (`NoteCardBuilder.media`). The Mac rated adapter (`PipelineFile.cardFacts`) and the Memo
/// adapter (phone rows + the Mac's quiet rows) must yield the same marker for the same note.
final class NoteCardMediaParityTests: XCTestCase {

    private func meta(_ m: MemoMetadata) -> Data { try! JSONEncoder().encode(m) }

    private func ratedRow(for memo: Memo) -> PipelineFile {
        let pf = MemoNoteProjection.file(for: memo)
        if pf.sourceType == .capture { pf.transcript = memo.annotationText }
        return pf
    }

    private func bothMedia(_ memo: Memo) -> (memo: NoteCardModel.Chip?, row: NoteCardModel.Chip?) {
        (NoteCardBuilder.media(for: memo.cardFacts()), NoteCardBuilder.media(for: ratedRow(for: memo).cardFacts))
    }

    func testVoiceMemoShowsMicAndLengthOnBothAdapters() {
        let m = Memo(audioFilename: "a.m4a", duration: 83, transcript: "Walked past the bakery.")
        let (a, b) = bothMedia(m)
        XCTAssertEqual(a, b)
        XCTAssertEqual(a, .init(text: "1:23", systemImage: SourceKind.voiceMemo.glyph))
    }

    func testVideoKeepsItsSourceGlyphOnAnAudioRow() {
        let m = Memo(audioFilename: "v.m4a", duration: 125, title: "Standup", transcript: "Planning",
                     metadataData: meta(MemoMetadata(sourceType: MemoMetadata.Source.video)))
        let (a, b) = bothMedia(m)
        XCTAssertEqual(a, b)
        XCTAssertEqual(a, .init(text: "2:05", systemImage: SourceKind.video.glyph))
    }

    func testBookCaptureShowsTheBookGlyphChapterAndLength() {
        let m = Memo(audioFilename: "b.m4a", duration: 40,
                     transcript: "> Focus is a skill.\n\nMy take: yes",
                     metadataData: meta(MemoMetadata(bookTitle: "Deep Work", bookChapter: "4")))
        let (a, b) = bothMedia(m)
        XCTAssertEqual(a, b)
        XCTAssertEqual(a?.systemImage, SourceKind.audiobookQuote.glyph)
        XCTAssertTrue(a?.text.hasSuffix("0:40") == true, a?.text ?? "nil")
    }

    func testLinkCaptureShowsTheLinkGlyphAndDomain() {
        let sc = SharedContent(type: .url, url: "https://www.example.com/post", urlTitle: "A Post")
        let m = Memo(sharedContentData: try! JSONEncoder().encode(sc))
        let (a, b) = bothMedia(m)
        XCTAssertEqual(a, b)
        XCTAssertEqual(a, .init(text: "example.com", systemImage: SourceKind.captureURL.glyph))
    }

    func testTypedNoteShowsNoMarker() {
        let m = Memo(transcript: "Buy milk",
                     metadataData: try! JSONSerialization.data(withJSONObject: ["mediaSource": "typed"]))
        let (a, b) = bothMedia(m)
        XCTAssertNil(a)
        XCTAssertNil(b)
    }
}
