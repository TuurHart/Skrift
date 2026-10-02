import XCTest

/// Q265 (C115): the note card's chip row wraps to at most 2 lines, then a "+N" chip.
/// The decision is `ChipLineBreaker.plan` (Shared/UI/ChipFlow.swift), pure so it needs no view.
final class ChipLineBreakerTests: XCTestCase {
    private func plan(_ widths: [CGFloat], max: CGFloat = 100, spacing: CGFloat = 4,
                      lines: Int = 2, plus: CGFloat = 20) -> ChipLineBreaker.Plan {
        ChipLineBreaker.plan(widths: widths, overflowWidth: { _ in plus },
                             maxWidth: max, spacing: spacing, maxLines: lines)
    }

    func testEverythingFitsOnOneLine() {
        let p = plan([30, 30, 30])   // 30+4+30+4+30 = 98
        XCTAssertEqual(p, .init(visible: 3, lineCounts: [3], hidden: 0))
    }

    func testWrapsToSecondLineInOrder() {
        let p = plan([40, 40, 40, 40])   // line 1: 40+4+40 = 84; line 2: 40+4+40
        XCTAssertEqual(p, .init(visible: 4, lineCounts: [2, 2], hidden: 0))
    }

    func testOverTwoLinesGetsPlusN() {
        // Five 40s need 3 lines. Keep 3 + "+2": line 1 = 40,40; line 2 = 40 + "+2".
        let p = plan([40, 40, 40, 40, 40])
        XCTAssertEqual(p.visible, 3)
        XCTAssertEqual(p.hidden, 2)
        XCTAssertEqual(p.lineCounts, [2, 2])
    }

    func testEightChipsKeepsAsManyAsFitPlusOverflowChip() {
        let p = plan([40, 40, 40, 40, 40, 40, 40, 40])
        XCTAssertEqual(p.visible, 3)
        XCTAssertEqual(p.hidden, 5)
        XCTAssertEqual(p.lineCounts.reduce(0, +), p.visible + 1)
    }

    func testOverflowChipWidthMatters() {
        // 3 shown + "+2" only fits when "+2" is narrow enough for line 2 (40 + 4 + w <= 100).
        XCTAssertEqual(plan([40, 40, 40, 40, 40], plus: 56).visible, 3)
        XCTAssertEqual(plan([40, 40, 40, 40, 40], plus: 57).visible, 2)
    }

    func testChipWiderThanRowIsClampedAndTakesALine() {
        let p = plan([300, 30], max: 100)
        XCTAssertEqual(p, .init(visible: 2, lineCounts: [1, 1], hidden: 0))
    }

    func testAlwaysShowsFirstChip() {
        let p = plan([300, 300, 300], max: 100, plus: 50)
        XCTAssertEqual(p.visible, 1)
        XCTAssertEqual(p.hidden, 2)
    }

    func testEmpty() {
        XCTAssertEqual(plan([]), .init(visible: 0, lineCounts: [], hidden: 0))
    }

    func testSingleLineModeNeverWraps() {
        let p = plan([40, 40, 40], lines: 1)   // 40+4+40+4+40 = 128 > 100
        XCTAssertEqual(p.lineCounts.count, 1)
        XCTAssertGreaterThan(p.hidden, 0)
    }
}
