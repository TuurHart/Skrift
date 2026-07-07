import XCTest
@testable import SkriftMobile

/// Index behaviour with the deterministic `MockEmbedder` and an in-memory store —
/// no model assets, no network (the engine-quality question was settled by the
/// bake-off spike, not unit tests).
final class EmbeddingIndexTests: XCTestCase {

    private func snap(_ id: UUID, title: String? = nil, body: String,
                      tags: [String] = [], date: Date = .init()) -> MemoSnapshot {
        MemoSnapshot(id: id, title: title, summary: nil, body: body,
                     place: nil, tags: tags, createdAt: date)
    }

    private func makeIndex(_ engine: MockEmbedder) -> EmbeddingIndex {
        EmbeddingIndex(store: EmbeddingStore(inMemory: true), engine: engine)
    }

    func testSweepInsertsGistPlusChunkRows() async throws {
        let engine = MockEmbedder()
        let index = makeIndex(engine)
        let id = UUID()
        let sentence = "Dit is een zin met precies acht woorden erin. "
        let longBody = String(repeating: sentence, count: 80) // ~640 words → >1 chunk

        let stats = try await index.sweep([snap(id, body: longBody)])
        XCTAssertEqual(stats.embedded, 1)
        let rows = try await index.rowCount(for: id)
        XCTAssertGreaterThanOrEqual(rows, 3) // gist + ≥2 chunks
    }

    func testResweepSkipsUnchangedAndReembedsEdited() async throws {
        let engine = MockEmbedder()
        let index = makeIndex(engine)
        let id = UUID()

        _ = try await index.sweep([snap(id, body: "original thought about pricing")])
        let second = try await index.sweep([snap(id, body: "original thought about pricing")])
        XCTAssertEqual(second, EmbeddingIndex.SweepStats(embedded: 0, skipped: 1, removed: 0))

        let third = try await index.sweep([snap(id, body: "edited thought about pricing")])
        XCTAssertEqual(third.embedded, 1)
    }

    func testSweepRemovesOrphanedMemos() async throws {
        let engine = MockEmbedder()
        let index = makeIndex(engine)
        let keep = UUID(), prune = UUID()

        _ = try await index.sweep([snap(keep, body: "keep me"), snap(prune, body: "prune me")])
        let stats = try await index.sweep([snap(keep, body: "keep me")])
        XCTAssertEqual(stats.removed, 1)
        let remaining = try await index.rowCount(for: prune)
        XCTAssertEqual(remaining, 0)
    }

    func testSearchRanksByRegisteredSimilarity() async throws {
        let engine = MockEmbedder()
        // Pricing cluster shares an axis; gardening is orthogonal.
        engine.register("pricing", [1, 0, 0, 0, 0, 0, 0, 0])
        engine.register("cost money", [0.9, 0.1, 0, 0, 0, 0, 0, 0])
        engine.register("tomatoes", [0, 0, 1, 0, 0, 0, 0, 0])
        let index = makeIndex(engine)

        let pricing = UUID(), garden = UUID()
        _ = try await index.sweep([
            snap(pricing, body: "the pricing decision for the app"),
            snap(garden, body: "the tomatoes on the balcony need sun"),
        ])

        let results = try await index.search("how should it cost money")
        XCTAssertEqual(results.first?.memoID, pricing)
        let pricingScore = results.first(where: { $0.memoID == pricing })!.score
        let gardenScore = results.first(where: { $0.memoID == garden })!.score
        XCTAssertGreaterThan(pricingScore, RetrievalTuning.searchFloor)
        XCTAssertLessThan(gardenScore, pricingScore)
    }

    func testRelatedExcludesSelfAndRanks() async throws {
        let engine = MockEmbedder()
        engine.register("pricing", [1, 0, 0, 0, 0, 0, 0, 0])
        engine.register("subscription", [0.95, 0.05, 0, 0, 0, 0, 0, 0])
        engine.register("tomatoes", [0, 0, 1, 0, 0, 0, 0, 0])
        let index = makeIndex(engine)

        let a = UUID(), b = UUID(), c = UUID()
        _ = try await index.sweep([
            snap(a, body: "pricing ramble"),
            snap(b, body: "subscription doubts"),
            snap(c, body: "tomatoes again"),
        ])

        let related = try await index.related(to: a)
        XCTAssertFalse(related.contains { $0.memoID == a })
        XCTAssertEqual(related.first?.memoID, b)
    }

    func testModelRevChangeInvalidatesRows() async throws {
        let store = EmbeddingStore(inMemory: true)
        let id = UUID()
        _ = try await EmbeddingIndex(store: store, engine: MockEmbedder())
            .sweep([snap(id, body: "stable text")])

        // Same store, new engine rev → the row's rev no longer matches → re-embed.
        final class MockV2: EmbeddingEngine {
            let modelRev = "mock-2"
            func prepare() async throws {}
            func embed(_ text: String, isQuery: Bool) async throws -> [Float] {
                [1, 0, 0, 0, 0, 0, 0, 0]
            }
        }
        let stats = try await EmbeddingIndex(store: store, engine: MockV2())
            .sweep([snap(id, body: "stable text")])
        XCTAssertEqual(stats.embedded, 1)
    }
}
