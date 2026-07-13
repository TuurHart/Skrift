import Foundation

/// Same-id `Memo` rows are a fact of life since 2026-07-12: a CloudKit re-sync
/// materialized exact-clone rows (same UUID), and content-DIVERGING same-id rows
/// are deliberately never auto-healed (the P0 lesson — that's a human call). The
/// phone HEALS exact clones (`MemoDeduper`: detach blob refs → trash), but every
/// READER must stay duplicate-tolerant regardless — clones exist until the heal
/// syncs, and divergent pairs exist indefinitely.
///
/// This is the ONE keeper rule both apps share, so the phone's deduper and the
/// Mac's reconcile sweep always pick the SAME row for an id.
enum MemoDuplicates {
    /// Content weight — the row carrying the most user content wins.
    static func score(_ m: Memo) -> Int {
        (m.transcript?.count ?? 0) + (m.annotationText?.count ?? 0) + (m.title?.count ?? 0)
    }

    /// Exact-clone check — the ONLY case the phone auto-heals: same words, same
    /// audio reference, recorded within a second.
    static func isContentClone(_ a: Memo, of b: Memo) -> Bool {
        a.transcript == b.transcript &&
        a.annotationText == b.annotationText &&
        a.title == b.title &&
        a.audioFilename == b.audioFilename &&
        abs(a.recordedAt.timeIntervalSince(b.recordedAt)) < 1
    }

    /// THE row to treat as "the memo" among same-id rows: alive beats trashed (a
    /// healed clone must never shadow its keeper), then most content, then latest
    /// edit; a full tie keeps the FIRST (the phone's pre-existing rule, and stable).
    static func keeper(of rows: [Memo]) -> Memo? {
        rows.enumerated().min { a, b in
            let (ai, am) = a, (bi, bm) = b
            let aAlive = am.deletedAt == nil, bAlive = bm.deletedAt == nil
            if aAlive != bAlive { return aAlive }
            let aScore = score(am), bScore = score(bm)
            if aScore != bScore { return aScore > bScore }
            if am.lastEditedAt != bm.lastEditedAt { return am.lastEditedAt > bm.lastEditedAt }
            return ai < bi
        }?.element
    }

    /// One row per id — duplicate-tolerant iteration for sweeps and other readers.
    /// Input order is preserved (each group collapses onto the position of its
    /// first occurrence).
    static func canonicalRows(_ memos: [Memo]) -> [Memo] {
        var order: [UUID] = []
        var groups: [UUID: [Memo]] = [:]
        for m in memos {
            if groups[m.id] == nil { order.append(m.id) }
            groups[m.id, default: []].append(m)
        }
        return order.compactMap { keeper(of: groups[$0] ?? []) }
    }
}
