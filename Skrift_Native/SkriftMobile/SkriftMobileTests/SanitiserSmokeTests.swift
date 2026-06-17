import XCTest
@testable import SkriftMobile

/// Phase 0 smoke test — proves the SHARED deterministic name-linker (`Sanitiser`,
/// `Skrift_Native/Shared/Naming/`) compiles AND executes on iOS, not just on the Mac.
/// The engine is wired into the phone's flow + review UI in Phase 2; this only
/// verifies the shared code runs here and matches the documented risk-tiering.
/// (Full behavioral coverage lives in the desktop `SanitiserTests`/`NamingGoldenTests`
/// — the SAME source file, so the behavior is identical by construction.)
final class SanitiserSmokeTests: XCTestCase {

    /// A distinctive first name (not a common word, not shared) auto-commits its
    /// first mention to `[[Canonical]]` — the opt-out happy path, on-device.
    func testDistinctiveFirstNameAutoLinksOnDevice() {
        let people = [Person(canonical: "[[Hendri van Niekerk]]",
                             aliases: ["Hendri van Niekerk", "Hendri"],
                             short: "Hendri",
                             lastModifiedAt: "2026-01-01T00:00:00Z")]
        let result = Sanitiser.process(text: "Met up with Hendri today.", people: people)
        XCTAssertTrue(result.sanitised.contains("[[Hendri van Niekerk]]"),
                      "distinctive first name should auto-link on-device — got: \(result.sanitised)")
    }

    /// A common-word first name ("Rose") is risk-tiered to a *suggestion* (dotted,
    /// commit-on-click), NOT auto-written — the FP guard runs on-device too.
    func testCommonWordNameIsSuggestedNotAutoLinked() {
        let people = [Person(canonical: "[[Rose Baker]]",
                             aliases: ["Rose Baker", "Rose"],
                             short: "Rose",
                             lastModifiedAt: "2026-01-01T00:00:00Z")]
        let result = Sanitiser.process(text: "Rose came by.", people: people)
        XCTAssertFalse(result.sanitised.contains("[[Rose Baker]]"),
                       "common-word first name must NOT auto-link — got: \(result.sanitised)")
        XCTAssertFalse(result.ambiguous.isEmpty,
                       "common-word name should surface as a suggestion")
    }
}
