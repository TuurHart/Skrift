import XCTest
@testable import SkriftMobile

/// Q167 (C210, C233, D30): the phone's review dots and print-to-wall read the
/// three stops through `ThreeBallScale`, so a legacy 0.7 is Important everywhere.
final class ImportanceStopsTests: XCTestCase {
    func testDotsMatchThreeBallBuckets() {
        XCTAssertEqual(ImportanceDots.filledCount(for: 0), 0)
        XCTAssertEqual(ImportanceDots.filledCount(for: 0.1), 1)
        XCTAssertEqual(ImportanceDots.filledCount(for: 0.3), 1)
        XCTAssertEqual(ImportanceDots.filledCount(for: 0.4), 2)
        XCTAssertEqual(ImportanceDots.filledCount(for: 0.6), 2)
        XCTAssertEqual(ImportanceDots.filledCount(for: 0.7), 3)   // recsj-095: was 2 on the phone
        XCTAssertEqual(ImportanceDots.filledCount(for: 0.8), 3)
        XCTAssertEqual(ImportanceDots.filledCount(for: 1.0), 3)
    }

    func testWallPrintsAtTheTopBallOnly() {
        func fires(_ s: Double) -> Bool {
            WallPrinter.shouldEnqueue(significance: s, alreadyPrinted: false, alreadyQueued: false)
        }
        XCTAssertTrue(fires(0.7))    // recsj-090: a legacy 0.7 never printed
        XCTAssertTrue(fires(0.8))
        XCTAssertTrue(fires(1.0))
        XCTAssertFalse(fires(0.6))
        XCTAssertFalse(fires(0.3))
        XCTAssertFalse(fires(0))
    }

    func testDotsAndWallAgreeOnEveryGridValue() {
        for tenth in 0...10 {
            let v = Double(tenth) / 10
            let top = ImportanceDots.filledCount(for: v) == 3
            XCTAssertEqual(top,
                           WallPrinter.shouldEnqueue(significance: v, alreadyPrinted: false, alreadyQueued: false),
                           "dots and wall disagree at \(v)")
        }
    }
}
