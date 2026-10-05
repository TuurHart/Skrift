import Foundation

/// Q317 (perf, iPhone 13, 2,000 notes): the Books tab counted notes per book once PER ROW,
/// each time decoding `Memo.metadata` for every memo on the main actor (D-B2a, 879 ms in
/// the trace). The counts are now computed ONCE per memo-set version, in one pass, off the
/// main actor: main reads only the raw metadata blobs (no decode), a detached task decodes
/// just `bookID` out of them, and the result is cached against the version key.
///
/// The key is the repository's `memoSetVersion` (Q53, bumped per `save()`) plus the live
/// memo count, because CloudKit imports reach the `@Query` without passing through
/// `NotesRepository.save()`.
@MainActor
final class BookNotesCountCache {
    static let shared = BookNotesCountCache()

    struct Key: Hashable {
        let version: Int
        let count: Int
    }

    private var key: Key?
    private(set) var counts: [UUID: Int] = [:]
    /// How many passes actually ran (tests assert "once for N rows").
    private(set) var computeCount = 0

    init() {}

    /// The counts for `memos` at `newKey`; recomputes (off-main) only when the key differs
    /// from the last pass. `memos` must be the live rows (the Books `@Query`).
    func counts(for memos: [Memo], key newKey: Key) async -> [UUID: Int] {
        if key == newKey { return counts }
        let blobs = BookNotesJoin.metadataBlobs(of: memos)          // main: reads bytes only
        let result = await Task.detached(priority: .userInitiated) {
            BookNotesJoin.counts(fromBlobs: blobs)                   // off main: the decode
        }.value
        if Task.isCancelled { return counts }                        // superseded: keep the old key
        key = newKey
        counts = result
        computeCount += 1
        return result
    }
}

extension BookNotesJoin {
    /// Metadata blobs of the canonical live rows (one per memo id, trashed excluded), in
    /// the same row set `counts(in:)` walks. Raw bytes only: no JSON decode on the caller.
    static func metadataBlobs(of memos: [Memo]) -> [Data] {
        MemoDuplicates.canonicalRows(memos).compactMap { memo in
            memo.deletedAt == nil ? memo.metadataData : nil
        }
    }

    private struct BookIDProbe: Decodable { let bookID: UUID? }
    private static let bookIDKey = Data("\"bookID\"".utf8)

    /// Notes per book from raw metadata blobs. Same answer as `counts(in:)`: decodes only
    /// `bookID` (a blob without the key cannot carry one, so it is skipped unparsed).
    nonisolated static func counts(fromBlobs blobs: [Data]) -> [UUID: Int] {
        var counts: [UUID: Int] = [:]
        let decoder = JSONDecoder()
        for blob in blobs {
            guard blob.range(of: bookIDKey) != nil,
                  let id = (try? decoder.decode(BookIDProbe.self, from: blob))?.bookID else { continue }
            counts[id, default: 0] += 1
        }
        return counts
    }
}
