import XCTest
import AppKit

/// Q555: Command-Z is the tag Undo toast's Undo only while the toast shows. These cover the key
/// match and the monitor's take/pass decision; that the real Edit-menu Command-Z still reaches the
/// text view when no toast shows needs a person pressing the key.
@MainActor
final class TagUndoKeyTests: XCTestCase {
    private func key(_ chars: String, _ flags: NSEvent.ModifierFlags, repeating: Bool = false) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0,
                         windowNumber: 0, context: nil, characters: chars,
                         charactersIgnoringModifiers: chars, isARepeat: repeating, keyCode: 6)!
    }

    func testPlainCommandZMatches() {
        XCTAssertTrue(TagUndoKey.isUndoChord(characters: "z", flags: .command))
        XCTAssertTrue(TagUndoKey.isUndoChord(characters: "Z", flags: [.command, .capsLock]))
    }

    func testRedoAndOtherChordsDoNotMatch() {
        XCTAssertFalse(TagUndoKey.isUndoChord(characters: "z", flags: [.command, .shift]))
        XCTAssertFalse(TagUndoKey.isUndoChord(characters: "z", flags: [.command, .option]))
        XCTAssertFalse(TagUndoKey.isUndoChord(characters: "z", flags: [.command, .control]))
        XCTAssertFalse(TagUndoKey.isUndoChord(characters: "z", flags: []))
        XCTAssertFalse(TagUndoKey.isUndoChord(characters: "x", flags: .command))
        XCTAssertFalse(TagUndoKey.isUndoChord(characters: nil, flags: .command))
    }

    func testInstalledMonitorTakesCommandZAndRunsUndo() {
        let monitor = TagUndoKey.Monitor()
        var undone = 0
        monitor.install { undone += 1 }
        XCTAssertTrue(monitor.isInstalled)
        XCTAssertNil(monitor.handle(key("z", .command)), "the key is consumed so the editor never sees it")
        XCTAssertEqual(undone, 1)
        monitor.remove()
    }

    func testTypedLettersAndRedoPassThroughUntouched() {
        let monitor = TagUndoKey.Monitor()
        var undone = 0
        monitor.install { undone += 1 }
        XCTAssertNotNil(monitor.handle(key("z", [])))               // typing the letter z
        XCTAssertNotNil(monitor.handle(key("z", [.command, .shift]))) // Redo
        XCTAssertNotNil(monitor.handle(key("a", .command)))
        XCTAssertEqual(undone, 0)
        monitor.remove()
    }

    func testRemovedMonitorPassesCommandZThrough() {
        let monitor = TagUndoKey.Monitor()
        var undone = 0
        monitor.install { undone += 1 }
        monitor.remove()
        XCTAssertFalse(monitor.isInstalled)
        XCTAssertNotNil(monitor.handle(key("z", .command)), "no toast: Command-Z is the editor's")
        XCTAssertEqual(undone, 0)
    }

    func testKeyRepeatIsNotTakenSoOneUndoPerPress() {
        let monitor = TagUndoKey.Monitor()
        var undone = 0
        monitor.install { undone += 1 }
        XCTAssertNotNil(monitor.handle(key("z", .command, repeating: true)))
        XCTAssertEqual(undone, 0)
        monitor.remove()
    }
}
