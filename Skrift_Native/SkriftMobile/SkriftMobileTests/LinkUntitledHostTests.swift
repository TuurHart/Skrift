import XCTest
@testable import SkriftMobile

/// Q266 (C72): a shared link whose page gave no title is titled by its HOST on the phone too —
/// the same shared rule (`NoteTitle.captureTitle` → `LinkCard.hostTitle`) the Mac's link door
/// stores — never "Capture", never the raw URL, never its search-only article text.
@MainActor
final class LinkUntitledHostTests: XCTestCase {

    private func linkMemo(url: String?, urlTitle: String? = nil, text: String? = nil,
                          annotation: String? = nil) -> Memo {
        let memo = Memo(id: UUID(), audioFilename: "")
        memo.sharedContent = SharedContent(type: .url, url: url, urlTitle: urlTitle, text: text)
        memo.annotationText = annotation
        return memo
    }

    func testUntitledLinkRowIsTitledByItsHost() {
        let memo = linkMemo(url: "https://www.metro.example.org/a/very/long/path?x=1")
        XCTAssertEqual(memo.ladderTitle(), "metro.example.org")
        XCTAssertNotEqual(memo.ladderTitle(), "Capture")
    }

    func testTheCardTitleUsesTheSameHostRule() {
        let memo = linkMemo(url: "https://www.metro.example.org/a")
        XCTAssertEqual(memo.shareCaptureTitle, "metro.example.org", "www. dropped, like the Mac")
        XCTAssertEqual(memo.shareCaptureTitle, memo.ladderTitle())
    }

    func testArticleTextNeverTitlesALink() {
        // A fetch that found body text but no <title>: the article text is search-only (C72).
        let memo = linkMemo(url: "https://example.com/post", text: "Lorem ipsum dolor sit amet and more words")
        XCTAssertEqual(memo.ladderTitle(), "example.com")
    }

    func testPageTitleAndAnnotationStillWin() {
        XCTAssertEqual(linkMemo(url: "https://example.com", urlTitle: "A Post").ladderTitle(), "A Post")
        XCTAssertEqual(linkMemo(url: "https://example.com", annotation: "My take").ladderTitle(), "My take")
    }

    func testHostRuleMatchesTheMacDoor() {
        let raw = "https://www.metro.example.org/x"
        XCTAssertEqual(NoteTitle.captureTitle(SharedContent(type: .url, url: raw)),
                       LinkCard.hostTitle(URL(string: raw)!))
    }

    func testLinkWithNoHostFallsBackToCapture() {
        XCTAssertEqual(NoteTitle.captureTitle(SharedContent(type: .url)), "Capture")
        XCTAssertEqual(NoteTitle.captureTitle(SharedContent(type: .url, url: "not a url")), "Capture")
    }
}
