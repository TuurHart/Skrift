import XCTest

/// Q68 (C115 — ONE shared `NoteCardView`): Q65 found the same tagged note showing
/// `#studio` on the phone's row but only duration/source chips on the Mac's — the
/// Mac's `QueueRowView.cardModel` never turned `PipelineFile.tags` into chips at
/// all. Both card-model builders (`MemoCard.cardModel` on the phone,
/// `QueueRowView.cardModel` on the Mac) now route their note's tags through the
/// ONE shared `NoteCardModel.tagChips(for:)` (NoteCardView.swift) — proven here
/// directly, the same way `ChipCountParityTests` proves the shared RULE rather than
/// driving the live SwiftUI view (`QueueRowView` lives in Features/Sidebar, which
/// pulls in the whole pipeline/AppKit stack the host-less test bundle deliberately
/// keeps out).
final class CardChipParityTests: XCTestCase {

    func testMacNoteAndPhoneMemoWithSameTagsYieldIdenticalChips() {
        // The Mac's note (PipelineFile.tags) and the phone's note (Memo.tags) for
        // the "same" tagged note.
        let file = PipelineFile(id: "note-1", filename: "note-1.md", path: "/tmp/note-1.md", size: 0, sourceType: .capture)
        file.tags = ["studio", "Interview"]

        let memo = Memo(tags: ["studio", "Interview"])

        let macChips = NoteCardModel.tagChips(for: file.tags)
        let phoneChips = NoteCardModel.tagChips(for: memo.tags)

        XCTAssertEqual(macChips, phoneChips)
        XCTAssertEqual(macChips.map(\.text), ["#studio", "#Interview"])
        XCTAssertTrue(macChips.allSatisfy(\.isTag), "tag chips must carry isTag so the card renders them as tags, not plain chips")
    }

    func testNoTagsYieldsNoChips() {
        let file = PipelineFile(id: "note-2", filename: "note-2.md", path: "/tmp/note-2.md", size: 0, sourceType: .capture)
        let memo = Memo()

        XCTAssertEqual(NoteCardModel.tagChips(for: file.tags), [])
        XCTAssertEqual(NoteCardModel.tagChips(for: memo.tags), [])
    }
}
