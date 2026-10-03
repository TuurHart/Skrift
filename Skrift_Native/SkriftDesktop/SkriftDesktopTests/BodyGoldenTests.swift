import XCTest

/// Q15: v1's own body-computation code (`v1Body`, `testV1BodyGoldens`) is deleted along
/// with the rest of v1 (tag `v1-body`) — the recorded golden `.txt` files under
/// `test-fixtures/corpus/goldens/v1-body/` are DATA, not code, and stay on disk as the
/// permanent "v1 shape" baseline `BodyV2HarnessTests` and others still diff v2 against
/// (C5). `corpusRoot`/`goldenDir` below are the shared path constants those tests (and
/// `BodyGoldenQ23Tests`, `BodyDiffHarnessTests`) still need — kept for that reason only.
final class BodyGoldenTests: XCTestCase {

    static var corpusRoot: URL {
        CorpusSeed.fixtureRoot(file: #filePath)
    }

    static var goldenDir: URL {
        corpusRoot.appendingPathComponent("goldens/v1-body", isDirectory: true)
    }
}
