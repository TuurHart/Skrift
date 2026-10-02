import XCTest

/// Q177 (C239/C240/C161/C25): the list + note chrome that both apps used to type twice now
/// comes from `SharedCopy` / `ListChrome` / `Palette`. These pin the strings and numbers the
/// two apps read, so one side can't be re-tuned alone (parity audit list-sidebar-04..63,
/// note-empty-01, capture-quick-03/09, note-lock-01).
final class ListChromeCopyTests: XCTestCase {

    func testEmptyPaneIsOneStringAndGlyph() {
        XCTAssertEqual(SharedCopy.emptyPaneTitle, "Select a note")
        XCTAssertFalse(SharedCopy.emptyPaneGlyph.isEmpty)
    }

    func testHeaderStyleIsOneSetOfNumbers() {
        XCTAssertEqual(ListChrome.headerSize, 11.5)
        XCTAssertEqual(ListChrome.headerKerning, 0.5)
        XCTAssertEqual(ListChrome.subtitleSize, 11)
        XCTAssertEqual(ListChrome.relatedHeader, "RELATED")
        XCTAssertEqual(ListChrome.relatedSubtitle, "similar in meaning")
    }

    func testAccentSoftIsOneToken() {
        XCTAssertEqual(Palette.accentSoftAlpha, 0.13)
    }

    func testSearchAndNewNoteAccessibilityNames() {
        XCTAssertEqual(SharedCopy.clearSearchLabel, "Clear search")
        XCTAssertEqual(SharedCopy.newNoteLabel, "New note")
        XCTAssertTrue(SharedCopy.newNoteTooltip.hasPrefix(SharedCopy.newNoteLabel))
        XCTAssertTrue(SharedCopy.newNoteTooltip.contains("⌘N"), "the tooltip keeps the shortcut")
    }

    func testLockedScreenSaysHiddenNotEncryptedOnBothApps() {
        for auth in ["Face ID", "Touch ID or your password"] {
            let body = SharedCopy.lockedBody(authName: auth)
            XCTAssertTrue(body.contains("hidden, not encrypted"), body)
            XCTAssertTrue(body.contains(auth), body)
        }
        XCTAssertEqual(SharedCopy.lockedTitleFallback, "Locked note")
        XCTAssertEqual(LockedRow.placeholderTitle, SharedCopy.lockedTitleFallback)
        XCTAssertEqual(NoteVisibility.placeholderTitle, SharedCopy.lockedTitleFallback)
        XCTAssertEqual(SharedCopy.unlockVerb, "Unlock")
    }

    func testBrandNewNoteTitlePromptIsAddATitle() {
        XCTAssertEqual(SharedCopy.titlePrompt(ghosts: []), "Add a title")
        XCTAssertEqual(SharedCopy.titlePrompt(ghosts: [nil, nil]), "Add a title")
        XCTAssertEqual(SharedCopy.titlePrompt(ghosts: ["", "  \n"]), "Add a title")
        // An untitled note with words ghosts its first line (information the phone shows too).
        XCTAssertEqual(SharedCopy.titlePrompt(ghosts: ["", "Call the plumber"]), "Call the plumber")
        XCTAssertEqual(SharedCopy.titlePrompt(ghosts: ["Plumbing", "Call the plumber"]), "Plumbing")
    }

    /// list-sidebar-63: a RATED Mac row with no title and no words falls to the taxonomy
    /// word ("Voice note"), not the descriptor label ("Voice memo").
    func testRatedMacRowWithNoWordsUsesEmptyTitleFallback() {
        let voice = PipelineFile(id: "v1", filename: "memo_v1.m4a", path: "/tmp/v1.m4a", size: 0, sourceType: .audio)
        let c = NoteCardBuilder.content(for: voice.cardFacts)
        XCTAssertEqual(c.snippet, voice.sourceKind.emptyTitleFallback)
        XCTAssertEqual(c.snippet, "Voice note")

        let typed = NoteCardFacts(kind: .typedNote)
        XCTAssertEqual(NoteCardBuilder.content(for: typed).snippet, "Note")
    }
}
