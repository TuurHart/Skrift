import XCTest
@testable import SkriftMobile

/// Pure-logic coverage for the Live Activity caption diet: the banner shows
/// ~2 lines, so pushes carry a word-aligned ~220-char tail instead of the
/// whole growing transcript (ActivityKit's content budget is small and every
/// push re-serializes the state).
final class RecordingActivityCaptionTests: XCTestCase {

    func testShortCaptionPassesThroughUntouched() {
        XCTAssertEqual(RecordingActivityManager.displayCaption("hello there"), "hello there")
        XCTAssertEqual(RecordingActivityManager.displayCaption(""), "")
    }

    func testAtTheCapPassesThroughUntouched() {
        let exactly = String(repeating: "a", count: 220)
        XCTAssertEqual(RecordingActivityManager.displayCaption(exactly), exactly)
    }

    func testLongCaptionKeepsAWordAlignedTail() {
        let words = (0..<200).map { "word\($0)" }
        let full = words.joined(separator: " ")
        let out = RecordingActivityManager.displayCaption(full)

        XCTAssertTrue(out.hasPrefix("…"))
        XCTAssertLessThanOrEqual(out.count, 221)   // "…" + ≤220-char tail
        let body = String(out.dropFirst())
        // The body is a genuine suffix of the caption…
        XCTAssertTrue(full.hasSuffix(body))
        // …and starts at a word boundary (no partial leading word, no space).
        XCTAssertFalse(body.hasPrefix(" "))
        let firstWord = body.split(separator: " ").first.map(String.init) ?? ""
        XCTAssertTrue(words.contains(firstWord), "leading word was cut mid-token: \(firstWord)")
    }

    func testGiantUnbrokenTokenFallsBackToRawTail() {
        let full = String(repeating: "x", count: 500)
        let out = RecordingActivityManager.displayCaption(full)
        XCTAssertTrue(out.hasPrefix("…"))
        XCTAssertEqual(out.count, 221)   // "…" + the raw 220 tail
    }
}
