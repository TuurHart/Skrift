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
@MainActor
enum MemoDeduper {
    static func run(_ repository: NotesRepository) {
        let groups = Dictionary(grouping: repository.allMemos(), by: \.id)
            .filter { $0.value.count > 1 }
        guard !groups.isEmpty else { return }
        for (id, rows) in groups {
            // Keeper = the row with the most content (ties keep the first).
            let sorted = rows.sorted { score($0) > score($1) }
            let keeper = sorted[0]
            for clone in sorted.dropFirst() {
                guard isContentClone(clone, of: keeper) else {
                    DevLog.log("dedupe: same id \(id) but content DIFFERS — left alone")
                    continue
                }
                clone.audioFilename = ""             // the keeper owns the blobs —
                var meta = clone.metadata            // the purge must not follow these
                meta?.imageManifest = nil
                clone.metadata = meta
                clone.deletedAt = Date()
                DevLog.log("dedupe: trashed clone row of \(id)")
            }
        }
        repository.save()
    }

    private static func score(_ m: Memo) -> Int {
        (m.transcript?.count ?? 0) + (m.annotationText?.count ?? 0) + (m.title?.count ?? 0)
    }

    static func isContentClone(_ a: Memo, of b: Memo) -> Bool {
        a.transcript == b.transcript &&
        a.annotationText == b.annotationText &&
        a.title == b.title &&
        a.audioFilename == b.audioFilename &&
        abs(a.recordedAt.timeIntervalSince(b.recordedAt)) < 1
    }
}
