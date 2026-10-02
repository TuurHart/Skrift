import XCTest
import Foundation

/// Q122: the Mac header chip, the sidebar row and the capture strip all spell a source kind
/// the same way, because they all read `SourceKind.label` (the phone chip does too). One link
/// used to read "Shared link" (phone chip, Mac strip) and "Link" (Mac row + header).
final class MacHeaderChipLabelsTests: XCTestCase {

    private func kind(_ sharedType: String?, capture: Bool = true) -> SourceKind {
        SourceKind.classify(hasBook: false, media: nil, sharedType: sharedType,
                            isCaptureRow: capture, hasAudio: false)
    }

    func testCaptureStripUsesTheSharedLabelNotItsOwnSpelling() {
        XCTAssertEqual(kind("url").stripLabel(domain: nil), "Link")
        XCTAssertEqual(kind("text").stripLabel(domain: nil), "Text")
        XCTAssertEqual(kind("image").stripLabel(domain: nil), "Image")
        XCTAssertEqual(kind("file").stripLabel(domain: nil), "File")
        XCTAssertEqual(kind(nil).stripLabel(domain: nil), "Capture")
    }

    func testStripAppendsTheDomainForALink() {
        XCTAssertEqual(kind("url").stripLabel(domain: "swiftwithmajid.com"), "Link · swiftwithmajid.com")
        XCTAssertEqual(kind("url").stripLabel(domain: ""), "Link")
    }

    func testStripLabelStartsWithTheRowLabelForEveryKind() {
        let kinds: [SourceKind] = [.audiobookQuote, .video, .captureURL, .captureImage, .captureText,
                                   .captureFile, .captureOther, .appleNote, .voiceMemo, .typedNote]
        for k in kinds {
            XCTAssertEqual(k.stripLabel(domain: nil), k.label)
            XCTAssertTrue(k.stripLabel(domain: "a.com").hasPrefix(k.label))
        }
    }
}
