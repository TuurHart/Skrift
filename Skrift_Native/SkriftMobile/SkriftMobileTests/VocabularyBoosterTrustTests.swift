import XCTest
@testable import SkriftMobile

/// The custom-vocab booster trust guard (`VocabularyBooster.allReplacementsTrusted`).
/// Tightened 2026-06-15 after the device repro where the spotter over-fired and mangled
/// "hello testing testing my name is tiuri and my book is skrift" into
/// "Tuur Skrift Tiuri Tuur and my book is Skrift Skrift": a boost is now kept ONLY when
/// EVERY applied replacement is trusted, so one distant spotter-rescue drops the whole
/// boost back to the clean unboosted transcript.
final class VocabularyBoosterTrustTests: XCTestCase {
    func testKeepsOnlyWhenEveryAppliedReplacementIsTrusted() {
        // A real correction (original ~ canonical, ignoring case) is trusted → kept.
        XCTAssertTrue(VocabularyBooster.allReplacementsTrusted([("Skrift", "Skrift", [])]))
        XCTAssertTrue(VocabularyBooster.allReplacementsTrusted([("skrift", "Skrift", [])]))

        // One distant spotter-rescue mixed in ("hello"→"Tuur") drops the WHOLE boost.
        XCTAssertFalse(VocabularyBooster.allReplacementsTrusted([
            ("skrift", "Skrift", []), ("hello", "Tuur", []),
        ]))

        // Nothing applied → nothing to keep.
        XCTAssertFalse(VocabularyBooster.allReplacementsTrusted([]))

        // A registered ALIAS makes an otherwise-distant mishear trusted (the user's
        // "add 'cherry' as an alias of Tuur" path) → kept.
        XCTAssertTrue(VocabularyBooster.allReplacementsTrusted([("cherry", "Tuur", ["cherry"])]))
    }
}
