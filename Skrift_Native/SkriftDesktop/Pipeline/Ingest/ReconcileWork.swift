import Foundation

/// Q364 (D186): work counters for the Mac reconcile pass, so `MacReconcileWorkTests` can hold
/// the steady-state cost of a pass: no asset blob fetched, O(1) `Memo` fetches, no metadata
/// re-serialise, no save when nothing changed. Bumped at the sites that cost; read by tests
/// only. Lock-guarded because the metadata builder can run off the main actor (the background
/// ingest's `prepare`).
enum ReconcileWork {
    struct Counts: Equatable {
        /// `FetchDescriptor<Memo>` fetches / fetchCounts made by the reconcile pass.
        var memoFetches = 0
        /// Full-row `MemoAsset` fetches (each faults the rows' audio / photo blobs).
        var assetBlobFetches = 0
        /// Blob-free `MemoAsset` index fetches (`propertiesToFetch: memoID, kind`).
        var assetIndexFetches = 0
        /// Full builds of `ReconcileV2.Ingest.metadataJSON` (JSON parse + sorted re-serialise).
        var metadataSerialisations = 0
        /// `ModelContext.save()` calls made by the pass.
        var saves = 0
    }

    private static let lock = NSLock()
    private static var _counts = Counts()

    static var counts: Counts {
        lock.lock(); defer { lock.unlock() }
        return _counts
    }

    static func reset() {
        lock.lock(); _counts = Counts(); lock.unlock()
    }

    static func bump(_ key: WritableKeyPath<Counts, Int>) {
        lock.lock(); _counts[keyPath: key] += 1; lock.unlock()
    }
}
