import XCTest
@testable import SkriftMobile

/// StableHash: the launch-stable palette pick + the one avatar-initials rule (Shared/Naming).
/// Twin file, identical body; only the import header differs.
final class StableHashTests: XCTestCase {
    func testSameKeySameIndexAndInRange() {
        let id = "3F2504E0-4F89-11D3-9A0C-0305E82C3301"
        XCTAssertEqual(StableHash.index(id, count: 5), StableHash.index(id, count: 5))
        for k in ["", "a", id, "Åsa Ünal", "日本語"] {
            let i = StableHash.index(k, count: 4)
            XCTAssertTrue((0..<4).contains(i), "\(k) -> \(i)")
        }
    }

    func testPinnedValueSoThePaletteNeverShiftsBetweenReleases() {
        // 31-hash of "Anna" computed by hand: ((65*31+110)*31+110)*31+97.
        XCTAssertEqual(StableHash.value("Anna"), 2_045_632)
        XCTAssertEqual(StableHash.index("Anna", count: 4), 0)
    }

    func testZeroCountIsSafe() {
        XCTAssertEqual(StableHash.index("x", count: 0), 0)
    }

    func testInitialsRule() {
        XCTAssertEqual(StableHash.initials("Anna de Vries"), "AD")   // first two words, not first+last
        XCTAssertEqual(StableHash.initials("anna"), "A")
        XCTAssertEqual(StableHash.initials("[[Jack Smith]]"), "JS")
        XCTAssertEqual(StableHash.initials(""), "?")
        XCTAssertEqual(StableHash.initials("   "), "?")
    }
}
