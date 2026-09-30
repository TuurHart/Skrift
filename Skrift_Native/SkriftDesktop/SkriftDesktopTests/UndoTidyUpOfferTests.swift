import XCTest
import Foundation

/// Q81: the note's ⋯ "Undo tidy-up" item shows exactly while `undo` would put something
/// back (`BodyNormaliseMigration.canUndo`), and the wording lives in `NoteMenuItem`.
final class UndoTidyUpOfferTests: XCTestCase {

    private func tempLedger() -> BodyNormaliseMigration.Ledger {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("q81-ledger-\(UUID().uuidString)")
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        return .init(directory: dir)
    }

    private final class Box { var text: String?; init(_ t: String?) { text = t } }

    private func body(_ box: Box) -> BodyNormaliseMigration.Body {
        .init(name: "transcript", get: { box.text }, set: { box.text = $0 })
    }

    private let original = "We sat\n\n[[img_001]]\n\n down by the kiln."

    func testNoOfferBeforeAnyTidyUp() {
        let box = Box(original)
        XCTAssertFalse(BodyNormaliseMigration.canUndo(id: "a", bodies: [body(box)], ledger: tempLedger()))
    }

    func testOfferedAfterTheTidyUpAndGoneAfterUndo() {
        let ledger = tempLedger()
        let box = Box(original)
        BodyNormaliseMigration.run(id: "a", bodies: [body(box)], manifestCount: 1,
                                   machineText: true, legacyShape: false, ledger: ledger)
        XCTAssertTrue(BodyNormaliseMigration.canUndo(id: "a", bodies: [body(box)], ledger: ledger))
        BodyNormaliseMigration.undo(id: "a", bodies: [body(box)], ledger: ledger)
        XCTAssertFalse(BodyNormaliseMigration.canUndo(id: "a", bodies: [body(box)], ledger: ledger))
        XCTAssertEqual(box.text, original)
    }

    func testNotOfferedOnceTheBodyWasEditedAfterwards() {
        let ledger = tempLedger()
        let box = Box(original)
        BodyNormaliseMigration.run(id: "a", bodies: [body(box)], manifestCount: 1,
                                   machineText: true, legacyShape: false, ledger: ledger)
        box.text = "Edited afterwards.\n\n[[img_001]]"
        XCTAssertFalse(BodyNormaliseMigration.canUndo(id: "a", bodies: [body(box)], ledger: ledger))
    }

    func testNotOfferedForACleanNote() {
        let ledger = tempLedger()
        let box = Box("Already v2.\n\n[[img_001]]\n\nDone.")
        BodyNormaliseMigration.run(id: "a", bodies: [body(box)], manifestCount: 1,
                                   machineText: true, legacyShape: false, ledger: ledger)
        XCTAssertFalse(BodyNormaliseMigration.canUndo(id: "a", bodies: [body(box)], ledger: ledger))
    }

    func testMenuWording() {
        XCTAssertEqual(NoteMenuItem.undoTidyUp.label, "Undo tidy-up")
        XCTAssertFalse(NoteMenuItem.undoTidyUp.systemImage.isEmpty)
    }
}
