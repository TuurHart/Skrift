import XCTest

/// Q545 (D224, mock Q542 "Picture sizes"): small is the picture itself, longest side a third of the
/// text width; large fills the text width at any height; nothing is cropped or capped.
final class PictureSizeRuleTests: XCTestCase {

    private let column: CGFloat = 362
    private let wide = CGSize(width: 3000, height: 2000)      // 3:2
    private let tall = CGSize(width: 3000, height: 4000)      // 3:4

    func testSmallWideIsAThirdOnItsLongestSide() {
        XCTAssertEqual(NoteAttachment.pictureSize(natural: wide, size: .small, column: column), CGSize(width: 121, height: 80))
    }

    func testSmallTallIsAThirdOnItsLongestSide() {
        XCTAssertEqual(NoteAttachment.pictureSize(natural: tall, size: .small, column: column), CGSize(width: 90, height: 121))
    }

    func testSmallSquareIsASquare() {
        XCTAssertEqual(NoteAttachment.pictureSize(natural: CGSize(width: 800, height: 800), size: .small, column: column),
                       CGSize(width: 121, height: 121))
    }

    func testLargeFillsTheWidthAndTallHasNoHeightLimit() {
        XCTAssertEqual(NoteAttachment.pictureSize(natural: wide, size: .large, column: column), CGSize(width: 362, height: 241))
        XCTAssertEqual(NoteAttachment.pictureSize(natural: tall, size: .large, column: column), CGSize(width: 362, height: 483))
        // A full-length screenshot is as tall as it is; the old 320 cap is gone.
        let shot = NoteAttachment.pictureSize(natural: CGSize(width: 1170, height: 2532), size: .large, column: column)
        XCTAssertEqual(shot, CGSize(width: 362, height: 783))
    }

    func testNothingIsCroppedAtEitherSize() {
        for natural in [wide, tall, CGSize(width: 1000, height: 1000), CGSize(width: 4000, height: 900), CGSize(width: 700, height: 3100)] {
            for size in [NoteAttachment.Size.small, .large] {
                let s = NoteAttachment.pictureSize(natural: natural, size: size, column: column)
                // The drawn shape keeps the picture's own, to within the rounding of whole points.
                XCTAssertEqual(s.width / s.height, natural.width / natural.height,
                               accuracy: (natural.width / natural.height) * 0.03 + 0.02, "\(natural) \(size)")
                if size == .small { XCTAssertEqual(max(s.width, s.height), 121) }
                else { XCTAssertEqual(s.width, 362) }
            }
        }
    }

    func testAnUnknownShapeIsSixteenByNine() {
        XCTAssertEqual(NoteAttachment.pictureSize(natural: nil, size: .small, column: column), CGSize(width: 121, height: 68))
        XCTAssertEqual(NoteAttachment.pictureSize(natural: .zero, size: .large, column: column), CGSize(width: 362, height: 204))
    }

    func testWideScreensMeasureAgainstAtMost720() {
        XCTAssertEqual(NoteAttachment.pictureColumn(column: 900, wide: true), 720)
        XCTAssertEqual(NoteAttachment.pictureColumn(column: 500, wide: true), 500)
        XCTAssertEqual(NoteAttachment.pictureColumn(column: 900, wide: false), 900)
    }

    func testThePhoneHoldMenuPutsTheSizeSwitchFirstAndKeepsEveryOtherVerbInOrder() {
        let menu = NoteAttachment.phoneHoldMenu(size: .small, paragraph: 1, count: 3, hasFile: true, isMedia: true, editing: true)
        XCTAssertEqual(menu, [.setSize(.large), .copy, .share, .save(toPhotos: true), .moveUp, .moveDown, .delete])
        let reading = NoteAttachment.phoneHoldMenu(size: .large, paragraph: 0, count: 1, hasFile: true, isMedia: false, editing: false)
        XCTAssertEqual(reading, [.setSize(.small), .copy, .share, .save(toPhotos: false)])
        // The Mac's right-click list keeps its own order.
        XCTAssertEqual(NoteAttachment.holdMenu(size: .small, paragraph: 1, count: 3, hasFile: true, isMedia: true, editing: true).first, .copy)
    }
}
