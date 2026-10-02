import XCTest
@testable import SkriftMobile

/// Q236: the embedder's single-flight cold load, and the downloader's glob.
final class Q236ModelLoadingTests: XCTestCase {

    private final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var n = 0
        func bump() { lock.lock(); n += 1; lock.unlock() }
        var value: Int { lock.lock(); defer { lock.unlock() }; return n }
    }
    private struct Stop: Error {}

    /// Two concurrent `prepare()` calls — with a transcription active, so the wait loop
    /// suspends the actor — must start ONE load, not two 295 MB loads.
    func testConcurrentPrepareStartsOneLoad() async {
        let loads = Counter()
        let embedder = GemmaEmbedder(loader: {
            loads.bump()
            try await Task.sleep(for: .milliseconds(150))
            throw Stop()   // EmbeddingGemma needs the real assets; counting starts is the point
        })
        TranscriptionActivity.begin()
        async let a: Void = { try? await embedder.prepare() }()
        async let b: Void = { try? await embedder.prepare() }()
        try? await Task.sleep(for: .milliseconds(100))
        TranscriptionActivity.end()
        _ = await (a, b)
        XCTAssertEqual(loads.value, 1)
    }

    func testGlobMatchesWhatMLXPasses() {
        typealias D = ResumableModelDownloader
        XCTAssertTrue(D.glob("*.safetensors", matches: "model-00001-of-00002.safetensors"))
        XCTAssertTrue(D.glob("*.json", matches: "config.json"))
        XCTAssertFalse(D.glob("*.json", matches: "config.json.bak"))
        XCTAssertTrue(D.glob("*", matches: "anything"))
        XCTAssertTrue(D.glob("config.json", matches: "config.json"))
        XCTAssertFalse(D.glob("config.json", matches: "other.json"))
        XCTAssertTrue(D.glob("model*.safetensors", matches: "model-1.safetensors"))
        XCTAssertFalse(D.glob("model*.safetensors", matches: "x-model-1.safetensors"))
        // flag 0: `*` crosses `/` (same as the hand-written matcher it replaces)
        XCTAssertTrue(D.glob("*.json", matches: "sub/dir/config.json"))
    }
}
