import XCTest
import Foundation

/// The one launch-argument parser both apps and every headless harness share (Q209).
/// Flag names are load-bearing: `plan/*.sh` and `RUN.md` pass them.
final class LaunchArgsTests: XCTestCase {
    private let argv = ["Skrift", "-ratefile", "a,b", "0.4", "-keep", "-corpus=/tmp/c", "-last"]

    func testValueAfterReadsTheNextArgument() {
        XCTAssertEqual(LaunchArgs.value(after: "-ratefile", in: argv), "a,b")
        XCTAssertEqual(LaunchArgs.value(after: "-keep", in: argv), "-corpus=/tmp/c")
    }

    func testValueAfterAcceptsTheEqualsForm() {
        XCTAssertEqual(LaunchArgs.value(after: "-corpus", in: argv), "/tmp/c")
    }

    func testValueAfterIsNilWhenAbsentOrLast() {
        XCTAssertNil(LaunchArgs.value(after: "-vault", in: argv))
        XCTAssertNil(LaunchArgs.value(after: "-last", in: argv))
    }

    func testValuesAfterReturnsExactlyNOrNil() {
        XCTAssertEqual(LaunchArgs.values(after: "-ratefile", count: 2, in: argv), ["a,b", "0.4"])
        XCTAssertNil(LaunchArgs.values(after: "-last", count: 2, in: argv))
        XCTAssertNil(LaunchArgs.values(after: "-vault", count: 1, in: argv))
        // The last argument has nothing after it, even for n = 1.
        XCTAssertNil(LaunchArgs.values(after: "-last", count: 1, in: argv))
    }

    func testHasMatchesBareAndEqualsForms() {
        XCTAssertTrue(LaunchArgs.has("-keep", in: argv))
        XCTAssertTrue(LaunchArgs.has("-corpus", in: argv))
        XCTAssertFalse(LaunchArgs.has("-kee", in: argv))
        XCTAssertFalse(LaunchArgs.has("-isolatedRun", in: argv))
    }

    func testIsolatedFlagNameIsUnchanged() {
        XCTAssertEqual(LaunchArgs.isolatedFlag, "-isolatedRun")
    }
}
