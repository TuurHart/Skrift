import XCTest

/// Q385b: the block rules both apps draw from (`NoteAttachment` in Shared): the hold /
/// right-click menu, move and delete on the stored body, Set All's filenames, the card words
/// for a photo and the captured PDF, and the iPad/Mac width caps (D202, mock Q384).
final class NoteBlockRulesTests: XCTestCase {

    private let body = "First line.\n\n[[img_001]]\n\nMiddle.\n\n[[vid_001]]\n\nLast."

    func testMoveUpAndDownSwapsTheBlockParagraph() {
        XCTAssertEqual(NoteAttachment.moving("[[vid_001]]", by: -1, in: body),
                       "First line.\n\n[[img_001]]\n\n[[vid_001]]\n\nMiddle.\n\nLast.")
        XCTAssertEqual(NoteAttachment.moving("[[vid_001]]", by: 1, in: body),
                       "First line.\n\n[[img_001]]\n\nMiddle.\n\nLast.\n\n[[vid_001]]")
        XCTAssertEqual(NoteAttachment.moving("[[img_001]]", by: -1, in: body),
                       "[[img_001]]\n\nFirst line.\n\nMiddle.\n\n[[vid_001]]\n\nLast.")
    }

    func testMoveAtTheEdgeOrOfAnUnknownBlockLeavesTheBody() {
        let top = "[[file_001]]\n\nText."
        XCTAssertEqual(NoteAttachment.moving("[[file_001]]", by: -1, in: top), top)
        XCTAssertEqual(NoteAttachment.moving("[[file_009]]", by: 1, in: top), top)
    }

    func testDeleteTakesOnlyTheBlockParagraph() {
        XCTAssertEqual(NoteAttachment.deleting("[[vid_001]]", in: body),
                       "First line.\n\n[[img_001]]\n\nMiddle.\n\nLast.")
        XCTAssertEqual(NoteAttachment.deleting("[[vid_002]]", in: body), body)
    }

    func testMoveBlockIsThePhotoMoveForAnyMarker() {
        XCTAssertEqual(BodyFormat.moveBlock(literal: "[[vid_001]]", in: body, toParagraph: 0),
                       "[[vid_001]]\n\nFirst line.\n\n[[img_001]]\n\nMiddle.\n\nLast.")
        XCTAssertEqual(BodyFormat.movePhoto(marker: 1, in: body, toParagraph: 0),
                       BodyFormat.moveBlock(literal: "[[img_001]]", in: body, toParagraph: 0))
    }

    func testBlockMenuOffersTheOtherSizeAndOnlyPossibleMoves() {
        let first = NoteAttachment.blockActions(size: .small, paragraph: 0, count: 3, shareable: true)
        XCTAssertEqual(first, [.setSize(.large), .moveDown, .share, .delete])
        let last = NoteAttachment.blockActions(size: .large, paragraph: 2, count: 3, shareable: false)
        XCTAssertEqual(last, [.setSize(.small), .moveUp, .delete])
        XCTAssertEqual(NoteAttachment.BlockAction.setSize(.large).title, "View as Large")
        XCTAssertEqual(NoteAttachment.BlockAction.setSize(.small).title, "View as Small")
    }

    func testSetAllCoversPhotosVideosFilesAndThePDF() {
        let v = NoteAttachment.makeEntry(owner: UUID(), number: 1, originalName: "clip.mov", byteCount: 10)
        let names = NoteAttachment.allFilenames(attachments: [v],
                                                photos: [ImageManifestEntry(filename: "img_a.jpg", offsetSeconds: 0)],
                                                pdf: "manual.pdf")
        XCTAssertEqual(names, [v.filename, "img_a.jpg", "manual.pdf"])
        XCTAssertEqual(NoteAttachment.settingAll(.large, filenames: names), names)
        XCTAssertNil(NoteAttachment.settingAll(.small, filenames: names))
    }

    func testPhotoAndPDFCardsSayWhatTheyAre() {
        let photo = NoteAttachment.photoCard(filename: "img_1.jpg", byteCount: nil)
        XCTAssertEqual(photo.title, "Photo")
        XCTAssertTrue(photo.thumb)
        let pdf = NoteAttachment.pdfCard(name: "manual.pdf", pages: 38, byteCount: nil)
        XCTAssertEqual(pdf.subtitle, "PDF document · 38 pages")
        XCTAssertEqual(pdf.badge, "PDF")
        XCTAssertFalse(pdf.thumb)
    }

    func testWideScreensCapMediaAndCards() {
        XCTAssertEqual(NoteAttachment.blockWidth(column: 900, wide: true, largeMedia: true), 720)
        XCTAssertEqual(NoteAttachment.blockWidth(column: 900, wide: true, largeMedia: false), 520)
        XCTAssertEqual(NoteAttachment.blockWidth(column: 361, wide: false, largeMedia: true), 361)
        XCTAssertEqual(NoteAttachment.videoMaxHeight(wide: false), 420)
        XCTAssertEqual(NoteAttachment.videoMaxHeight(wide: true), 560)
    }
}
