import Foundation

/// The retrieval brain's engine seam (P8, `JOURNAL_RETRIEVAL_PLAN.md`).
///
/// **Shared source (`Shared/Retrieval/`)** — platform-neutral (Foundation only) so the
/// Mac adopts the identical engine in Phase 2. The production engine is
/// EmbeddingGemma-300M at dim 512 (decided by the 2026-07-07 bake-off,
/// `Skrift_Native/spikes/EmbeddingBakeoff/` — 10/10 vs Apple's 5/10); it lives
/// app-side (`GemmaEmbedder`) because it needs the CoreML-LLM package. Tests use
/// `MockEmbedder` so the unit suite stays asset-free (established engine pattern).
protocol EmbeddingEngine {
    /// Identifies the model + dim. A rev change invalidates every stored row —
    /// the sweep re-embeds; there is deliberately NO other migration path.
    var modelRev: String { get }
    /// Load the model (and download its assets if needed). Idempotent.
    func prepare() async throws
    /// One unit-normalized vector for `text`. `isQuery` selects the retrieval-query
    /// vs retrieval-document task prompt (EmbeddingGemma is trained asymmetric).
    func embed(_ text: String, isQuery: Bool) async throws -> [Float]
}

enum RetrievalMath {
    /// Cosine over unit vectors = dot product. Plain loop: 512 floats × a few
    /// thousand rows is well under a millisecond; revisit with vDSP only if the
    /// corpus outgrows it.
    static func dot(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count else { return 0 }
        var s: Float = 0
        for i in 0..<a.count { s += a[i] * b[i] }
        return s
    }

    static func normalize(_ v: [Float]) -> [Float] {
        var n: Float = 0
        for x in v { n += x * x }
        n = sqrt(n)
        guard n > 0 else { return v }
        return v.map { $0 / n }
    }
}

/// Deterministic test engine. Register a keyword → vector pair and any text
/// containing that keyword embeds to it; unregistered text gets a stable
/// hash-seeded pseudo-vector (near-orthogonal to everything registered).
final class MockEmbedder: EmbeddingEngine {
    let modelRev = "mock-1"
    private(set) var embedCount = 0
    private var registry: [(key: String, vector: [Float])] = []
    let dimension: Int

    init(dimension: Int = 8) { self.dimension = dimension }

    func register(_ key: String, _ vector: [Float]) {
        registry.append((key, RetrievalMath.normalize(vector)))
    }

    func prepare() async throws {}

    func embed(_ text: String, isQuery: Bool) async throws -> [Float] {
        embedCount += 1
        if let hit = registry.first(where: { text.localizedCaseInsensitiveContains($0.key) }) {
            return hit.vector
        }
        // Stable pseudo-vector from a djb2 seed — same text, same vector.
        var seed: UInt64 = 5381
        for b in text.utf8 { seed = seed &* 33 &+ UInt64(b) }
        var v = [Float](repeating: 0, count: dimension)
        for i in 0..<dimension {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            v[i] = Float(Int64(bitPattern: seed) % 1000) / 1000.0
        }
        return RetrievalMath.normalize(v)
    }
}
