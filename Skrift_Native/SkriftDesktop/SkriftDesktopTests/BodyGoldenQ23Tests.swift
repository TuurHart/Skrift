import XCTest

/// Q23 (gate+): the R25/R33/R74 corpus fixtures SPEC.md's required-difference table names
/// but the generated corpus never had (see `_missing_fixtures` in `expected-differences.json`).
/// `manifest.json`, `expected-differences.json` and `generate.py` are protected and additive-
/// only for this item, so the 4 new note folders (`pic-during-pause-two-shots`,
/// `pic-burst-same-offset`, `ingress-p3-five-clips-one-picture`, `migrated-stale-name-offsets`)
/// are NOT listed in `manifest.json` — this is a SECOND, additive path/registration set reading
/// `manifest-q23.json` / `expected-differences-q23.json` instead, mirroring `BodyGoldenTests`/
/// `BodyDiffHarnessTests`'s v1-body recipe and C5 classification.
///
/// Q15: v1's own body-computation code (`v1Body`, `testV1BodyGoldensQ23`,
/// `testV1MismatchesExpectBodyExactlyOnRegisteredSlugsQ23`) is deleted along with the rest of
/// v1 (tag `v1-body`) — the recorded golden `.txt` files stay on disk as data.
/// `manifestURL`/`expectedDifferencesURL`/`goldenDir`/`loadExpectedDifferences()` below are the
/// shared constants `BodyV2HarnessTests` still reads — kept for that reason only.
final class BodyGoldenQ23Tests: XCTestCase {

    static var manifestURL: URL { BodyGoldenTests.corpusRoot.appendingPathComponent("manifest-q23.json") }
    static var expectedDifferencesURL: URL { BodyGoldenTests.corpusRoot.appendingPathComponent("expected-differences-q23.json") }
    /// New golden files only — never touches an existing `goldens/v1-body/<slug>.txt`.
    static var goldenDir: URL { BodyGoldenTests.goldenDir }

    static func loadExpectedDifferences() throws -> [String: [String]] {
        let obj = try JSONSerialization.jsonObject(with: Data(contentsOf: expectedDifferencesURL)) as? [String: Any] ?? [:]
        var out: [String: [String]] = [:]
        for (key, value) in obj where !key.hasPrefix("_") {
            out[key] = (value as? [String]) ?? []
        }
        return out
    }
}
