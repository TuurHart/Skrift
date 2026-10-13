import XCTest

/// Q391: the block's hold / right-click menu as mock Q384 draws it (pick 6) — Copy, Share, Save,
/// then View as Small/Large, the possible moves and Delete — one list for both apps.
final class NoteHoldMenuTests: XCTestCase {

    func testAVideoInTheMiddleGetsEveryVerbInTheMocksOrder() {
        let menu = NoteAttachment.holdMenu(size: .small, paragraph: 1, count: 3, hasFile: true, isMedia: true, editing: true)
        XCTAssertEqual(menu, [.copy, .share, .save(toPhotos: true), .setSize(.large), .moveUp, .moveDown, .delete])
    }

    func testAFileSavesOutsidePhotosAndTheFirstBlockCannotMoveUp() {
        let menu = NoteAttachment.holdMenu(size: .large, paragraph: 0, count: 3, hasFile: true, isMedia: false, editing: true)
        XCTAssertEqual(menu, [.copy, .share, .save(toPhotos: false), .setSize(.small), .moveDown, .delete])
        XCTAssertEqual(NoteAttachment.BlockAction.save(toPhotos: false).title, "Save to Downloads")   // the Mac's word
        XCTAssertEqual(NoteAttachment.BlockAction.save(toPhotos: true).title, "Save to Photos")
        XCTAssertEqual(NoteAttachment.BlockAction.copy.title, "Copy")
    }

    func testABlockWhoseFileHasNotArrivedHasNoFileVerbs() {
        let menu = NoteAttachment.holdMenu(size: .small, paragraph: 2, count: 3, hasFile: false, isMedia: true, editing: true)
        XCTAssertEqual(menu, [.setSize(.large), .moveUp, .delete])
    }

    func testReadingKeepsTheFileVerbsAndTheSizeSwitchOnly() {
        let menu = NoteAttachment.holdMenu(size: .small, paragraph: 1, count: 3, hasFile: true, isMedia: false, editing: false)
        XCTAssertEqual(menu, [.copy, .share, .save(toPhotos: false), .setSize(.large)])
    }

    func testEveryVerbHasASymbol() {
        let all: [NoteAttachment.BlockAction] = [.copy, .share, .save(toPhotos: true), .save(toPhotos: false),
                                                 .setSize(.large), .setSize(.small), .moveUp, .moveDown, .delete]
        for a in all { XCTAssertFalse(a.symbol.isEmpty); XCTAssertFalse(a.title.isEmpty) }
    }
}
