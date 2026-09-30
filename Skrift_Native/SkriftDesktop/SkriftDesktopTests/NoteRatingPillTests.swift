import XCTest
import Foundation

/// Q85 (C94, C88): the header pill's pure logic — the step order of a tap and
/// the toast copy.
final class NoteRatingPillTests: XCTestCase {

    func testTapStepsNotRatedPassingUsefulImportantThenUnrates() {
        var v: Double? = nil
        var seen: [Int] = []
        for _ in 0..<5 {
            v = ThreeBallScale.stepped(v)
            seen.append(ThreeBallScale.step(for: v))
        }
        XCTAssertEqual(seen, [1, 2, 3, 0, 1])
    }

    func testTapWritesTheThreePersistedStopsAndZeroForUnrated() {
        XCTAssertEqual(ThreeBallScale.stepped(nil), 0.3)
        XCTAssertEqual(ThreeBallScale.stepped(0), 0.3)
        XCTAssertEqual(ThreeBallScale.stepped(0.3), 0.6)
        XCTAssertEqual(ThreeBallScale.stepped(0.6), 1.0)
        XCTAssertEqual(ThreeBallScale.stepped(1.0), 0)
    }

    func testLegacyGridValuesStepFromTheirBucket() {
        XCTAssertEqual(ThreeBallScale.stepped(0.1), 0.6)   // 0.1 = Passing -> Useful
        XCTAssertEqual(ThreeBallScale.stepped(0.5), 1.0)   // 0.5 = Useful -> Important
        XCTAssertEqual(ThreeBallScale.stepped(0.8), 0)     // 0.8 = Important -> Not rated
    }

    func testUnratingIsTheRatedToUnratedStepAndNamesTheConsequence() {
        XCTAssertEqual(ThreeBallScale.toastCopy(from: 3, to: 0), "Not rated · out of the queue, no export")
        XCTAssertEqual(ThreeBallScale.toastCopy(from: 0, to: 0), "Not rated · left alone")
        XCTAssertFalse(NoteConsent.isRated(ThreeBallScale.stepped(1.0)))
    }

    func testEachRatedStepIsNamed() {
        XCTAssertEqual(ThreeBallScale.toastCopy(from: 0, to: 1), "Passing · ready to process")
        XCTAssertEqual(ThreeBallScale.toastCopy(from: 1, to: 2), "Useful · ready to process")
        XCTAssertEqual(ThreeBallScale.toastCopy(from: 2, to: 3), "Important · ready to process")
    }
}
