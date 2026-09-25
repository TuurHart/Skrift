import XCTest

/// C9/C253/Q10: registered every body-generation engine (v1 then, v2 in Q11+) to run over
/// the whole corpus and class each note against v1's own recorded golden (`BodyGoldenTests`)
/// — never against v1 the person, v1 the CODE was only the change detector (C5).
///
/// Q15: v1's own engine (`V1Engine`) and its two classification tests
/// (`testEngineClassificationAgainstV1Golden`, `testV1MismatchesExpectBodyExactlyOnRegisteredSlugs`)
/// are deleted along with the rest of v1 (tag `v1-body`) — `BodyV2HarnessTests` now does the
/// live classification, comparing v2 against the recorded golden `.txt` files (data, not code).
/// `BodyEngine` and `loadExpectedDifferences()` below are kept: `BodyV2HarnessTests.V2Engine`
/// still conforms to the former, and still calls the latter.
final class BodyDiffHarnessTests: XCTestCase {

    // MARK: - the engine protocol

    /// One body-generation pipeline runnable over a corpus note.
    protocol BodyEngine {
        var name: String { get }
        func body(for note: CorpusSeed.Note, folder: URL) throws -> String
    }

    // MARK: - expected-differences.json (slug -> [R id])

    /// Keys starting with `_` are documentation (`_schema` is a string, `_missing_fixtures`
    /// an object) — never a slug, and not `[String]`-shaped, so this reads the file as
    /// loose JSON rather than decoding it as one homogeneous dictionary type.
    static func loadExpectedDifferences() throws -> [String: [String]] {
        let url = BodyGoldenTests.corpusRoot.appendingPathComponent("expected-differences.json")
        let obj = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any] ?? [:]
        var out: [String: [String]] = [:]
        for (key, value) in obj where !key.hasPrefix("_") {
            out[key] = (value as? [String]) ?? []
        }
        return out
    }

}
