import XCTest
import Foundation

/// Q179 (C78, C239): every source glyph and label comes from `SourceKind`. A Mac picture-only
/// import reads "Image" like a phone image share; rows show the source chip for video and
/// audiobook quote and the shared-item title + domain chip.
final class SourceGlyphParityTests: XCTestCase {

    private func chips(_ f: NoteCardFacts) -> [NoteCardModel.Chip] { NoteCardBuilder.content(for: f).chips }

    func testPictureOnlyMarkerReadsImageNotCapture() {
        // A Mac picture-only note: a capture row, no sharedContent, mediaSource "image".
        let kind = SourceKind.classify(hasBook: false, media: MemoMetadata.Source.image, sharedType: nil,
                                       isCaptureRow: true, hasAudio: false)
        XCTAssertEqual(kind, .captureImage)
        XCTAssertEqual(kind.label, "Image")
        XCTAssertEqual(kind.glyph, "photo")
        // Without the marker the same row falls to the generic capture word.
        let bare = SourceKind.classify(hasBook: false, media: nil, sharedType: nil,
                                       isCaptureRow: true, hasAudio: false)
        XCTAssertEqual(bare.label, "Capture")
    }

    func testPictureOnlyMemoClassifiesAsImage() throws {
        let m = Memo(audioFilename: "", recordedAt: Date(), transcript: "[[img_001]]", transcriptStatus: .done)
        m.metadataData = try JSONSerialization.data(withJSONObject: ["mediaSource": "image"])
        XCTAssertEqual(SourceKind.of(m), .captureImage)
        XCTAssertEqual(SourceKind.of(m).label, "Image")
    }

    func testPictureOnlyRowShowsTheImageChip() {
        let f = NoteCardFacts(kind: .captureImage, body: "[[img_001]]")
        XCTAssertEqual(chips(f).first, .init(text: "Image", systemImage: "photo"))
    }

    func testVideoRowShowsTheSourceChip() {
        let f = NoteCardFacts(kind: .video, body: "hello", durationSeconds: 60)
        XCTAssertEqual(chips(f).first, .init(text: SourceKind.video.label, systemImage: SourceKind.video.glyph))
    }

    func testAudiobookQuoteRowShowsTheBookGlyph() {
        let f = NoteCardFacts(kind: .audiobookQuote, body: "> a quote", book: .init(title: "Goats", chapter: "3"))
        XCTAssertTrue(chips(f).contains { $0.systemImage == SourceKind.audiobookQuote.glyph })
    }

    func testSharedLinkRowShowsTitleAndDomainChip() {
        let sc = SharedContent(type: .url, url: "https://www.example.com/a", urlTitle: "An article")
        let c = NoteCardBuilder.content(for: NoteCardFacts(kind: .captureURL, shared: sc))
        XCTAssertEqual(c.title, "An article")
        XCTAssertEqual(c.chips.first, .init(text: "Link", systemImage: "link"))
        XCTAssertTrue(c.chips.contains { $0.text == "example.com" })
    }

    func testEveryKindHasOneGlyphAndLabel() {
        let all: [SourceKind] = [.audiobookQuote, .video, .captureURL, .captureImage, .captureText,
                                 .captureFile, .captureOther, .appleNote, .voiceMemo, .typedNote]
        XCTAssertEqual(Set(all.map(\.glyph)).count, all.count, "two kinds share a glyph")
        XCTAssertEqual(Set(all.map(\.label)).count, all.count, "two kinds share a label")
    }
}
