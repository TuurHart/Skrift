import XCTest
import Foundation

/// Q492 (C294): `EmbeddingIndex` is an actor, and its sweep awaits the engine for every vector,
/// so a query can run at each suspension point. A query issued mid-sweep must see each memo
/// either as it was before its swap or as it is after — never with its old rows gone and only
/// some new ones in. Stress: an engine that suspends inside every embed, and a reader hammering
/// the index while the sweep re-embeds.
final class SweepReentrancyTests: XCTestCase {

    /// `MockEmbedder`'s vectors, but every embed SUSPENDS first, so the actor is free to run a
    /// waiting query in the middle of a sweep (the reentrancy window C294 is about).
    final class SuspendingEmbedder: EmbeddingEngine, @unchecked Sendable {
        let modelRev = "mock-1"
        private let inner = MockEmbedder()
        func prepare() async throws {}
        func embed(_ text: String, isQuery: Bool) async throws -> [Float] {
            try await Task.sleep(nanoseconds: 300_000)
            return try await inner.embed(text, isQuery: isQuery)
        }
    }

    private func snap(_ id: UUID, _ body: String) -> MemoSnapshot {
        MemoSnapshot(id: id, title: nil, summary: nil, body: body, place: nil, tags: [])
    }

    /// `n` chunks of ~250 words (each chunk is its own row after the gist).
    private func body(_ word: String, chunks n: Int) -> String {
        let sentence = "The \(word) kiln note keeps going with plenty of words in it here. "   // 13 words
        return String(repeating: sentence, count: 20 * n)
    }

    func testAQueryMidSweepSeesEachMemoBeforeOrAfterItsSwapNeverBetween() async throws {
        let index = EmbeddingIndex(store: EmbeddingStore(inMemory: true), engine: SuspendingEmbedder())
        let ids = (0..<6).map { _ in UUID() }
        let anchor = UUID()
        _ = try await index.sweep([snap(anchor, "anchor note about glaze")] + ids.map { snap($0, body("old", chunks: 2)) })
        var before: [UUID: Int] = [:]
        for id in ids { before[id] = try await index.rowCount(for: id) }

        // Re-embed every memo with a longer body, while a reader queries in a tight loop.
        let edited = ids.map { snap($0, body("new", chunks: 5)) }
        let done = Flag()
        let sweep = Task {
            defer { done.set() }
            return try await index.sweep([snap(anchor, "anchor note about glaze")] + edited)
        }
        var observed: [UUID: Set<Int>] = [:]
        var missingFromRelated = 0
        var reads = 0
        while !done.value {
            for id in ids {
                observed[id, default: []].insert(try await index.rowCount(for: id))
            }
            let related = Set(try await index.related(to: anchor).map(\.memoID))
            missingFromRelated += ids.filter { !related.contains($0) }.count
            reads += 1
        }
        _ = try await sweep.value
        var after: [UUID: Int] = [:]
        for id in ids { after[id] = try await index.rowCount(for: id) }

        XCTAssertGreaterThan(reads, 3, "the reader must actually interleave with the sweep")
        for id in ids {
            XCTAssertNotEqual(before[id], after[id], "precondition: the edit changes the row count")
            let allowed: Set<Int> = [before[id]!, after[id]!]
            XCTAssertTrue(observed[id, default: []].isSubset(of: allowed),
                          "saw \(observed[id]!.sorted()) rows; only \(allowed.sorted()) are whole states")
        }
        XCTAssertEqual(missingFromRelated, 0, "a memo mid-swap vanished from Related")
        XCTAssertTrue(observed.values.contains { $0.count == 2 }, "the reader saw some memos before AND after")
    }

    /// Set by the sweep task when it ends; read by the reader loop.
    private final class Flag: @unchecked Sendable {
        private let lock = NSLock()
        private var on = false
        var value: Bool { lock.lock(); defer { lock.unlock() }; return on }
        func set() { lock.lock(); on = true; lock.unlock() }
    }
}
