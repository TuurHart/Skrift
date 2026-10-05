import XCTest
import UIKit
@testable import SkriftMobile

/// Q321: a note opened from a search scrolls the first hit to the vertical MIDDLE of
/// the visible area (clamped at the top/bottom of the text) and paints every
/// occurrence in highlighter yellow with dark text.
final class SearchHitCenteringTests: XCTestCase {

    // MARK: the shared rule (pure)

    func testHitInTheMiddleOfALongNoteLandsAtTheVisibleCentre() {
        // 800-pt viewport, 100 top inset, 150 bottom inset → visible 550 pt, centre at
        // viewport y = 100 + 275 = 375. Hit at content y 5000 → offset = 5000 - 375.
        let y = SearchHitLook.centeredOffsetY(hitMidY: 5000, contentHeight: 12000,
                                              viewportHeight: 800, topInset: 100, bottomInset: 150)
        XCTAssertEqual(y, 5000 - 375, accuracy: 0.001)
        XCTAssertEqual(5000 - y, 375, accuracy: 0.001, "hit centre on screen = visible-area centre")
    }

    func testHitNearTheTopClampsToTheTopInset() {
        let y = SearchHitLook.centeredOffsetY(hitMidY: 40, contentHeight: 12000,
                                              viewportHeight: 800, topInset: 100, bottomInset: 150)
        XCTAssertEqual(y, -100, accuracy: 0.001)
    }

    func testHitAtTheEndClampsToTheBottom() {
        let y = SearchHitLook.centeredOffsetY(hitMidY: 11990, contentHeight: 12000,
                                              viewportHeight: 800, topInset: 100, bottomInset: 150)
        XCTAssertEqual(y, 12000 + 150 - 800, accuracy: 0.001)
    }

    func testShortNoteNeverScrollsPastTheTop() {
        let y = SearchHitLook.centeredOffsetY(hitMidY: 300, contentHeight: 400,
                                              viewportHeight: 800, topInset: 100, bottomInset: 0)
        XCTAssertEqual(y, -100, accuracy: 0.001)
    }

    func testMatchRangesFindsEveryOccurrenceIgnoringCaseAndAccents() {
        let r = SearchHitLook.matchRanges(of: "cafe", in: "Café, CAFE and a cafe.")
        XCTAssertEqual(r.count, 3)
    }

    // MARK: the editor

    private var window: UIWindow!

    @MainActor
    private func makeEditor(memo: Memo) -> (NoteBodyView.Coordinator, NoteBodyTextView) {
        let coordinator = NoteBodyView.Coordinator(memo: memo, onCommit: { _ in })
        let tv = NoteBodyTextView()
        tv.installAccessoryHosts()
        window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 800))
        window.addSubview(tv)
        window.makeKeyAndVisible()
        tv.frame = window.bounds
        coordinator.textView = tv
        coordinator.load(force: true)
        tv.layoutIfNeeded()
        return (coordinator, tv)
    }

    private func longNote(hitWord: String, paragraphs: Int, hitAt: Int) -> String {
        (0..<paragraphs).map { i in
            let filler = "Paragraph \(i) walks through the evening at some length and says very little of note, "
                + "then carries on for a second sentence so the paragraph wraps over several lines."
            return i == hitAt ? filler + " Then \(hitWord) appears." : filler
        }.joined(separator: "\n\n")
    }

    @MainActor
    func testFlashCentresTheHitAndPaintsItYellow() throws {
        let memo = Memo(audioFilename: "m.m4a", transcript: longNote(hitWord: "zeppelin", paragraphs: 60, hitAt: 45))
        let (c, tv) = makeEditor(memo: memo)
        c.flashSearchHit("zeppelin")
        // Let the re-aim passes settle.
        let settled = expectation(description: "settled")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { settled.fulfill() }
        wait(for: [settled], timeout: 3)

        let r = (tv.textStorage.string as NSString).range(of: "zeppelin")
        let rects = tv.rects(forCharacterRange: r)
        let union = try XCTUnwrap(rects.dropFirst().reduce(rects.first, { $0?.union($1) }))
        let inset = tv.adjustedContentInset
        let visibleMid = inset.top + (tv.bounds.height - inset.top - inset.bottom) / 2
        let screenMid = union.midY - tv.contentOffset.y
        XCTAssertEqual(screenMid, visibleMid, accuracy: 14, "the hit sits at the visible middle")

        let bg = tv.textStorage.attribute(.backgroundColor, at: r.location, effectiveRange: nil) as? UIColor
        XCTAssertEqual(bg, NoteBodyView.Coordinator.hexColor(SearchHitLook.fillHex), "highlighter yellow")
        let fg = tv.textStorage.attribute(.foregroundColor, at: r.location, effectiveRange: nil) as? UIColor
        XCTAssertEqual(fg, NoteBodyView.Coordinator.hexColor(SearchHitLook.textHex), "dark text on the yellow")
    }

    @MainActor
    func testEveryOccurrenceIsPainted() throws {
        let memo = Memo(audioFilename: "m.m4a", transcript: "tram one, then a second tram, and a Tram at the end")
        let (c, tv) = makeEditor(memo: memo)
        c.flashSearchHit("tram")
        let painted = SearchHitLook.matchRanges(of: "tram", in: tv.textStorage.string).filter {
            tv.textStorage.attribute(.backgroundColor, at: $0.location, effectiveRange: nil) != nil
        }
        XCTAssertEqual(painted.count, 3)
    }
}
