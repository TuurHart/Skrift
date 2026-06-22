import XCTest
@testable import SkriftMobile

/// Tests for the C3 capture-item display helpers added to MemoDisplay.swift.
final class CaptureDisplayTests: XCTestCase {

    // MARK: - isShareCapture detection

    func testShareCaptureDetection() {
        let urlCapture = makeMemo(type: .url)
        XCTAssertTrue(urlCapture.isShareCapture)

        let audioMemo = Memo(audioFilename: "memo_x.m4a")
        XCTAssertFalse(audioMemo.isShareCapture)

        // audioFilename empty but NO sharedContent → not a capture (invalid state)
        let noContent = Memo(audioFilename: "")
        XCTAssertFalse(noContent.isShareCapture)
    }

    // MARK: - shareCaptureGlyph

    func testShareCaptureGlyph() {
        XCTAssertEqual(makeMemo(type: .url).shareCaptureGlyph, "link")
        XCTAssertEqual(makeMemo(type: .text).shareCaptureGlyph, "text.quote")
        XCTAssertEqual(makeMemo(type: .image).shareCaptureGlyph, "photo")
    }

    // MARK: - shareCaptureTitle

    func testURLCaptureTitleUsesURLTitle() {
        let memo = makeMemo(type: .url, url: "https://example.com", urlTitle: "Example title")
        XCTAssertEqual(memo.shareCaptureTitle, "Example title")
    }

    func testURLCaptureTitleFallsBackToDomain() {
        let memo = makeMemo(type: .url, url: "https://swiftwithmajid.com/foo")
        XCTAssertEqual(memo.shareCaptureTitle, "swiftwithmajid.com")
    }

    func testTextCaptureTitleUsesFirstWords() {
        let text = "A note about Swift concurrency and actors and why they matter"
        let memo = makeMemo(type: .text, text: text)
        XCTAssertTrue(memo.shareCaptureTitle.hasPrefix("A note about Swift"))
    }

    func testImageCaptureTitleUsesAnnotation() {
        let memo = makeMemo(type: .image, annotationText: "Whiteboard from the meeting")
        XCTAssertEqual(memo.shareCaptureTitle, "Whiteboard from the meeting")
    }

    func testImageCaptureTitleFallsBackToImage() {
        let memo = makeMemo(type: .image)
        XCTAssertEqual(memo.shareCaptureTitle, "Image")
    }

    // MARK: - shareCaptureSnippet

    func testURLCaptureSnippetUsesAnnotation() {
        let memo = makeMemo(type: .url, url: "https://example.com",
                            annotationText: "Use this for the body editor")
        XCTAssertEqual(memo.shareCaptureSnippet, "Use this for the body editor")
    }

    func testURLCaptureSnippetFallsBackToDomainWhenNoAnnotation() {
        let memo = makeMemo(type: .url, url: "https://swiftwithmajid.com/foo")
        XCTAssertEqual(memo.shareCaptureSnippet, "swiftwithmajid.com")
    }

    // MARK: - shareCaptureTypeLabel

    func testTypeLabelValues() {
        XCTAssertEqual(makeMemo(type: .url).shareCaptureTypeLabel, "Shared link")
        XCTAssertEqual(makeMemo(type: .text).shareCaptureTypeLabel, "Shared text")
        XCTAssertEqual(makeMemo(type: .image).shareCaptureTypeLabel, "Shared image")
    }

    // MARK: - shareCaptureURLDomain

    func testURLDomainStripsWWW() {
        let memo = makeMemo(type: .url, url: "https://www.swiftwithmajid.com/post")
        XCTAssertEqual(memo.shareCaptureURLDomain, "swiftwithmajid.com")
    }

    func testURLDomainNilForNonURLCapture() {
        XCTAssertNil(makeMemo(type: .text, text: "Hello").shareCaptureURLDomain)
    }

    // MARK: - displayTitle fallthrough

    func testDisplayTitleUsesShareCaptureTitleWhenNoTranscript() {
        let memo = makeMemo(type: .url, url: "https://example.com", urlTitle: "The page title")
        XCTAssertEqual(memo.displayTitle, "The page title")
    }

    func testDisplayTitlePrefersUserSetTitle() {
        let memo = Memo.make(
            audioFilename: "", title: "My title",
            sharedContent: SharedContent(type: .url, url: "https://example.com", urlTitle: "Page title")
        )
        XCTAssertEqual(memo.displayTitle, "My title")
    }

    // MARK: - Helpers

    private func makeMemo(
        type: ShareContentType,
        url: String? = nil,
        urlTitle: String? = nil,
        text: String? = nil,
        imageFileName: String? = nil,
        annotationText: String? = nil
    ) -> Memo {
        Memo.make(
            audioFilename: "",
            sharedContent: SharedContent(
                type: type,
                url: url,
                urlTitle: urlTitle,
                text: text,
                fileName: imageFileName
            ),
            annotationText: annotationText
        )
    }
}
