import XCTest

/// Q284 / D169: the keyboard table both apps' `.commands` read. Asserting it here is what
/// keeps ⌘N from being bound to two verbs again.
final class AppShortcutsTests: XCTestCase {
    func testNewNoteIsCommandN() {
        XCTAssertEqual(AppShortcuts.newNote.glyphs, "⌘N")
    }

    func testRecordIsShiftCommandN() {
        XCTAssertEqual(AppShortcuts.record.glyphs, "⇧⌘N")
    }

    func testSearchIsCommandF() {
        XCTAssertEqual(AppShortcuts.search.glyphs, "⌘F")
    }

    func testMacSurfaces() {
        XCTAssertEqual(AppShortcuts.macNotes.glyphs, "⌘1")
        XCTAssertEqual(AppShortcuts.macReview.glyphs, "⌘2")
    }

    func testPhoneTabs() {
        XCTAssertEqual([AppShortcuts.tabNotes, AppShortcuts.tabBooks, AppShortcuts.tabReview, AppShortcuts.tabSettings].map(\.glyphs),
                       ["⌘1", "⌘2", "⌘3", "⌘4"])
    }

    func testNoChordIsBoundTwiceOnEitherPlatform() {
        XCTAssertEqual(Set(AppShortcuts.mac).count, AppShortcuts.mac.count)
        XCTAssertEqual(Set(AppShortcuts.phone).count, AppShortcuts.phone.count)
    }
}
