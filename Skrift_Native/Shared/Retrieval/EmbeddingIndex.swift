import Foundation
import SwiftData

/// A memo's index-relevant content, detached from the `@Model` so it can cross
/// into the index actor. Built on the main actor (`JournalIndexService`).
struct MemoSnapshot: Sendable {
    let id: UUID
    let title: String?
    /// Mac polish summary when present (`MemoEnhancement.summary`).
    let summary: String?
    /// Polished body when present, else the raw transcript. Speaker headers
    /// are stripped by the index, not the caller.
    let body: String
    let place: String?
    let tags: [String]
    let createdAt: Date
}

/// Similarity floors — CALIBRATED 2026-07-07 from the on-device histogram
/// (iPhone 13, real corpus, 5 runs × 2000 random gist pairs): p50 ≈ 0.31,
/// p90 ≈ 0.49, p99 ≈ 0.81. The old related floor (0.30) sat AT the random-pair
/// median — pure noise; 0.45 ≈ p90 on a deliberately NARROW test corpus (12
/// same-topic memos inflate the baseline), so it filters noise without
/// over-pruning a diverse one. Search floor stays bake-off-derived (query↔doc
/// is a different, lower distribution: expected μ 0.46 vs distractor μ 0.07).
/// Re-run Settings → "Log score histogram" as the corpus grows to re-check.
enum RetrievalTuning {
    static let searchFloor: Float = 0.25
    static let relatedFloor: Float = 0.45
    static let relatedK = 4
}

/// The retrieval index (P8): sweep-maintained embeddings + brute-force cosine
/// queries. One gist row + n chunk rows per memo; a memo's score = max over its
/// rows. All state lives in `EmbeddingStore`'s local container.
actor EmbeddingIndex {
    struct SweepStats: Equatable {
        var embedded = 0   // memos (re)embedded
        var skipped = 0    // unchanged, hash matched
        var removed = 0    // orphaned memos deleted from the index
    }

    private let store: EmbeddingStore
    private let engine: EmbeddingEngine
    private lazy var context = ModelContext(store.container)

    init(store: EmbeddingStore, engine: EmbeddingEngine) {
        self.store = store
        self.engine = engine
    }

    // ── sweep ──

    /// Hash-diff every snapshot against the stored rows: embed new/changed
    /// memos, skip unchanged ones, delete rows for memos that no longer exist
    /// (trash purge / prune). Saves per memo so an interrupted sweep resumes
    /// where it left off. `onProgress(done, total)` fires per snapshot (skips
    /// included) — the Mac gate's "Building the index — N of M".
    func sweep(_ snapshots: [MemoSnapshot],
               onProgress: (@Sendable (Int, Int) -> Void)? = nil) async throws -> SweepStats {
        var stats = SweepStats()
        let existing = try groupedRows()
        var seen = Set<UUID>()

        for (i, snap) in snapshots.enumerated() {
            defer { onProgress?(i + 1, snapshots.count) }
            seen.insert(snap.id)
            let body = MemoGist.stripSpeakerHeaders(snap.body)
            let gist = MemoGist.compose(title: snap.title, summary: snap.summary,
                                        body: body, place: snap.place,
                                        people: [], tags: snap.tags)
            let hash = MemoGist.textHash(gist + "\u{1}" + body)

            if let rows = existing[snap.id],
               let first = rows.first,
               first.textHash == hash, first.modelRev == engine.modelRev {
                stats.skipped += 1
                continue
            }

            try await engine.prepare()
            existing[snap.id]?.forEach { context.delete($0) }

            let gistVector = try await engine.embed(gist, isQuery: false)
            context.insert(MemoEmbedding(memoID: snap.id, chunkIndex: 0,
                                         charStart: 0, charEnd: 0,
                                         vector: gistVector, textHash: hash,
                                         modelRev: engine.modelRev))
            for (i, chunk) in MemoGist.chunks(body: body).enumerated() {
                let v = try await engine.embed(chunk.text, isQuery: false)
                context.insert(MemoEmbedding(memoID: snap.id, chunkIndex: i + 1,
                                             charStart: chunk.start, charEnd: chunk.end,
                                             vector: v, textHash: hash,
                                             modelRev: engine.modelRev))
            }
            try context.save()
            stats.embedded += 1
        }

        // Orphans: memos gone from the store (purged trash, pruned unrated).
        for (memoID, rows) in existing where !seen.contains(memoID) {
            rows.forEach { context.delete($0) }
            stats.removed += 1
        }
        try context.save()
        return stats
    }

    // ── queries (scores only — the UI applies floors/sorting/dates) ──

    /// Memos ranked against a free-text query (max cosine over each memo's rows).
    func search(_ query: String) async throws -> [(memoID: UUID, score: Float)] {
        try await engine.prepare()
        let qv = try await engine.embed(query, isQuery: true)
        return try scores(against: qv, excluding: nil)
    }

    /// Memos ranked against a memo's gist vector — powers Related and (sorted by
    /// date, floor-gated) Threads.
    func related(to memoID: UUID) throws -> [(memoID: UUID, score: Float)] {
        let rows = try groupedRows()
        guard let gist = rows[memoID]?.first(where: { $0.chunkIndex == 0 }) else { return [] }
        return try scores(against: gist.floats, excluding: memoID)
    }

    /// Row count per memo — cheap introspection for tests + a future status UI.
    func rowCount(for memoID: UUID) throws -> Int {
        try groupedRows()[memoID]?.count ?? 0
    }

    /// Calibration sample: cosine over random distinct GIST pairs (up to
    /// `limit`) — the raw material for the floor histogram.
    func gistPairScores(limit: Int) throws -> [Float] {
        let gists = try groupedRows().compactMap { $0.value.first { $0.chunkIndex == 0 }?.floats }
        guard gists.count > 1 else { return [] }
        var out: [Float] = []
        out.reserveCapacity(limit)
        for _ in 0..<limit {
            let a = Int.random(in: 0..<gists.count)
            var b = Int.random(in: 0..<gists.count)
            if a == b { b = (b + 1) % gists.count }
            out.append(RetrievalMath.dot(gists[a], gists[b]))
        }
        return out
    }

    private func scores(against qv: [Float], excluding: UUID?) throws -> [(memoID: UUID, score: Float)] {
        var best: [UUID: Float] = [:]
        for (memoID, rows) in try groupedRows() where memoID != excluding {
            for row in rows {
                let s = RetrievalMath.dot(qv, row.floats)
                if s > (best[memoID] ?? -1) { best[memoID] = s }
            }
        }
        return best.map { ($0.key, $0.value) }.sorted { $0.1 > $1.1 }
    }

    private func groupedRows() throws -> [UUID: [MemoEmbedding]] {
        let all = try context.fetch(FetchDescriptor<MemoEmbedding>())
        return Dictionary(grouping: all, by: { $0.memoID })
    }
}
