import Foundation
import SwiftData

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
        if dedupe(in: repository.context) { repository.save() }
    }

    /// The sweep core on any context (Q316: `SweepActor` runs it off the main thread).
    /// Mutates only; the CALLER saves. Returns true if it trashed a clone.
    nonisolated static func dedupe(in context: ModelContext) -> Bool {
        // Live memos only (trash-filtered, same as `allMemos()`) and NOT de-duplicated,
        // so every row here is alive and the clones are visible.
        let live = (try? context.fetch(FetchDescriptor<Memo>(
            predicate: #Predicate { $0.deletedAt == nil },
            sortBy: [SortDescriptor(\.recordedAt, order: .reverse)]))) ?? []
        // Cheap pre-check: a unique-id library (the normal case) builds a Set, not a
        // dictionary of arrays.
        var seen = Set<UUID>()
        var anyDuplicate = false
        for m in live where !seen.insert(m.id).inserted { anyDuplicate = true; break }
        guard anyDuplicate else { return false }
        let groups = Dictionary(grouping: live, by: \.id)
            .filter { $0.value.count > 1 }
        guard !groups.isEmpty else { return false }
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
        return true
    }
}
