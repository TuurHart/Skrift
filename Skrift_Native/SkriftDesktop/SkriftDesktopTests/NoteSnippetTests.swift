import XCTest

/// List-row snippets are plain text: no `**…**`, no `[[…]]` (Tuur 2026-09-27, Q69).
final class NoteSnippetTests: XCTestCase {
    func testSpeakerHeadersAndNameLinksBecomePlainText() {
        let body = "**Speaker 1:** Hello there.\n\n**[[Tiuri Hartog]]:** Hi, I met [[Roksana Gurova|Roks]] today."
        XCTAssertEqual(NoteSnippet.plain(body),
                       "Speaker 1: Hello there.\n\nTiuri Hartog: Hi, I met Roks today.")
    }

    func testPictureMarkersAndMemoLinks() {
        let body = "[[img_001]]Look at [[memo:0F0A1B2C-0000-4000-8000-000000000001|last week's plan]] now"
        XCTAssertEqual(NoteSnippet.plain(body), "Look at last week's plan now")
    }

    func testPlainTextIsUntouched() {
        XCTAssertEqual(NoteSnippet.plain("just a plain note, 2 * 3 = 6"), "just a plain note, 2 * 3 = 6")
    }

    func testNoRawMarkupSurvivesInARealisticConversation() {
        let s = NoteSnippet.plain("**Speaker 1:** a\n\n**Speaker 2:** b\n\n**[[Tiuri Hartog]]:** c")
        XCTAssertFalse(s.contains("**"))
        XCTAssertFalse(s.contains("[["))
    }
}
