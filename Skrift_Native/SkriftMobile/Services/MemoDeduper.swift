import Foundation

/// Trashes EXACT-clone memo rows that CloudKit sync can materialize (same UUID,
/// same content — 2026-07-12: a device re-sync duplicated 16 June memos and the
/// list's id-keyed dictionaries trapped → a launch crash loop). Conservative by
/// design (the P0 lesson: never destroy data):
/// - clones go to the TRASH (the 14-day Recently Deleted window), never hard-deleted
/// - a clone's file references are DETACHED first (audioFilename / imageManifest)
///   so the eventual trash purge can't delete blobs the keeper still owns
/// - same-id rows whose content DIFFERS are left alone (the id-keyed maps are
///   duplicate-tolerant since this incident) and logged for a human call.
///
/// The keeper choice + clone check are the SHARED `MemoDuplicates` rules — the
/// Mac's reconcile sweep picks the same keeper, so both apps agree on which row
/// IS the memo.
@MainActor
enum MemoDeduper {
    static func run(_ repository: NotesRepository) {
        // allMemos() is trash-filtered, so every row here is alive.
        let groups = Dictionary(grouping: repository.allMemos(), by: \.id)
            .filter { $0.value.count > 1 }
        guard !groups.isEmpty else { return }
        for (id, rows) in groups {
            guard let keeper = MemoDuplicates.keeper(of: rows) else { continue }
            for clone in rows where clone !== keeper {
                guard MemoDuplicates.isContentClone(clone, of: keeper) else {
                    DevLog.log("dedupe: same id \(id) but content DIFFERS — left alone")
                    continue
                }
                clone.audioFilename = ""             // the keeper owns the blobs —
                var meta = clone.metadata            // the purge must not follow these
                meta?.imageManifest = nil
                clone.metadata = meta
                clone.deletedAt = Date()
                clone.trashSeenAt = clone.deletedAt  // clones need no unseen grace — purge on schedule
                DevLog.log("dedupe: trashed clone row of \(id)")
            }
        }
        repository.save()
    }

    /// Kept as a pass-through so existing call sites/tests read the same.
    static func isContentClone(_ a: Memo, of b: Memo) -> Bool {
        MemoDuplicates.isContentClone(a, of: b)
    }
}
