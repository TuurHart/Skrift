import XCTest
@testable import SkriftMobile

/// Q526b: the launch/foreground Parakeet warm-up is single-flight, skips a warm or
/// never-downloaded model, and holds the embedder's ANE gate while it runs.
final class ASRPrewarmTests: XCTestCase {

    private final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var n = 0
        func bump() { lock.lock(); n += 1; lock.unlock() }
        var value: Int { lock.lock(); defer { lock.unlock() }; return n }
    }
    private final class Flag: @unchecked Sendable {
        private let lock = NSLock()
        private var v = false
        func set(_ x: Bool) { lock.lock(); v = x; lock.unlock() }
        var value: Bool { lock.lock(); defer { lock.unlock() }; return v }
    }
    private struct Stop: Error {}

    func testRequestsDuringALoadStartExactlyOneLoad() async throws {
        let loads = Counter()
        let prewarm = ASRPrewarm(isWarm: { false }, load: {
            loads.bump()
            try await Task.sleep(for: .milliseconds(200))
        })
        let first = prewarm.request(reason: "launch")
        XCTAssertNotNil(first)
        // launch + foreground + a second foreground, all while the load is in flight
        XCTAssertNil(prewarm.request(reason: "foreground"))
        XCTAssertNil(prewarm.request(reason: "foreground"))
        await first?.value
        XCTAssertEqual(loads.value, 1)
        // after it finishes, a new request is accepted again (and finds the model warm in prod)
        let again = prewarm.request(reason: "foreground")
        XCTAssertNotNil(again)
        await again?.value
    }

    func testWarmModelIsNotReloaded() async {
        let loads = Counter()
        let prewarm = ASRPrewarm(isWarm: { true }, load: { loads.bump() })
        await prewarm.request(reason: "foreground")?.value
        XCTAssertEqual(loads.value, 0)
        XCTAssertEqual(prewarm.loads, 0)
    }

    func testNeverDownloadedModelIsNotFetchedByTheHook() async {
        let loads = Counter()
        let prewarm = ASRPrewarm(isWarm: { false }, mayLoad: { false }, load: { loads.bump() })
        XCTAssertNil(prewarm.request(reason: "launch"))
        XCTAssertEqual(loads.value, 0)
        XCTAssertFalse(TranscriptionActivity.isActive)
    }

    func testActivityIsRaisedImmediatelyAndReleasedAfterwards() async throws {
        let prewarm = ASRPrewarm(isWarm: { false }, load: {
            try await Task.sleep(for: .milliseconds(100))
        })
        XCTAssertFalse(TranscriptionActivity.isActive)
        let t = prewarm.request(reason: "launch")
        XCTAssertTrue(TranscriptionActivity.isActive)   // synchronously, before the task runs
        await t?.value
        XCTAssertFalse(TranscriptionActivity.isActive)
    }

    func testFailedLoadReleasesTheGateAndAllowsRetry() async {
        let prewarm = ASRPrewarm(isWarm: { false }, load: { throw Stop() })
        await prewarm.request(reason: "launch")?.value
        XCTAssertFalse(TranscriptionActivity.isActive)
        let retry = prewarm.request(reason: "foreground")
        XCTAssertNotNil(retry)
        await retry?.value
    }

    /// The embedder's cold load must not START while the ASR warm-up is active.
    func testEmbedderLoadWaitsBehindTheAsrWarmup() async {
        let asrDone = Flag()
        let embedderStartedWhileAsrActive = Flag()
        let prewarm = ASRPrewarm(isWarm: { false }, load: {
            try await Task.sleep(for: .milliseconds(900))
            asrDone.set(true)
        })
        let embedder = GemmaEmbedder(loader: {
            embedderStartedWhileAsrActive.set(!asrDone.value)
            throw Stop()   // counting the start is the point; the real model needs assets
        })
        let warm = prewarm.request(reason: "foreground")   // before the sweep, as in SkriftApp
        let embed: Task<Void, Never> = Task { try? await embedder.prepare() }
        try? await Task.sleep(for: .milliseconds(300))
        XCTAssertFalse(asrDone.value)
        await warm?.value
        await embed.value
        XCTAssertFalse(embedderStartedWhileAsrActive.value, "embedder loaded while ASR warm-up held the ANE")
    }
}
