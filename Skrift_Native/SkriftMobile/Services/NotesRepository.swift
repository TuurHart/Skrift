import Foundation
import SwiftData

/// Owns the SwiftData `ModelContainer` for memos and exposes CRUD. Honors
/// `-inMemoryStore` so UI tests get a fresh, deterministic store per launch.
@MainActor
final class NotesRepository {
    static let shared = NotesRepository(inMemory: LaunchFlags.inMemoryStore)

    let container: ModelContainer
    var context: ModelContext { container.mainContext }

    init(inMemory: Bool) {
        let schema = Schema([Memo.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory)
        do {
            container = try ModelContainer(for: schema, configurations: config)
        } catch {
            fatalError("Unable to create ModelContainer for Memo: \(error)")
        }
    }

    func insert(_ memo: Memo) {
        context.insert(memo)
        save()
    }

    /// Newest first — the order the memos list renders. EXCLUDES trashed memos
    /// (`deletedAt != nil`), so every caller — list, search, and crucially
    /// SyncCoordinator's upload loop — automatically skips the trash.
    func allMemos() -> [Memo] {
        let descriptor = FetchDescriptor<Memo>(
            predicate: #Predicate { $0.deletedAt == nil },
            sortBy: [SortDescriptor(\.recordedAt, order: .reverse)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    /// Trashed memos, most recently deleted first (the Recently Deleted screen).
    func deletedMemos() -> [Memo] {
        let descriptor = FetchDescriptor<Memo>(
            predicate: #Predicate { $0.deletedAt != nil },
            sortBy: [SortDescriptor(\.deletedAt, order: .reverse)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    /// Lookup by id finds trashed memos too — Restore and purge need them.
    func memo(id: UUID) -> Memo? {
        let descriptor = FetchDescriptor<Memo>(predicate: #Predicate { $0.id == id })
        return try? context.fetch(descriptor).first
    }

    // MARK: - Trash (Recently Deleted)

    /// Move a memo to Recently Deleted. Audio, photos, and sidecars stay on disk
    /// so Restore is lossless; the startup purge removes them after
    /// `TrashPolicy.retention`. `date` is injectable for tests.
    func softDelete(_ memo: Memo, at date: Date = Date()) {
        memo.deletedAt = date
        save()
    }

    /// Bring a trashed memo back to the main list, untouched.
    func restore(_ memo: Memo) {
        memo.deletedAt = nil
        save()
    }

    /// The full-delete path: removes the memo's audio, its photos, and the
    /// word-timings + diarization sidecars, then the row itself. Used by
    /// Delete-Now in Recently Deleted and the startup purge. (MemoDetailView's
    /// delete mirrors the same cleanup inline.)
    func permanentlyDelete(_ memo: Memo) {
        if let url = memo.audioURL { try? FileManager.default.removeItem(at: url) }
        memo.metadata?.imageManifest?.forEach {
            try? FileManager.default.removeItem(at: AppPaths.recordingsDirectory.appendingPathComponent($0.filename))
        }
        WordTimingsStore().delete(for: memo.id)
        DiarizationStore().delete(for: memo.id)
        context.delete(memo)
        save()
    }

    /// Startup purge: permanently delete every memo trashed at least
    /// `TrashPolicy.retention` ago (inclusive). `now` is injectable for tests.
    @discardableResult
    func purgeExpiredTrash(now: Date = Date()) -> Int {
        let expired = deletedMemos().filter { memo in
            guard let deletedAt = memo.deletedAt else { return false }
            return now.timeIntervalSince(deletedAt) >= TrashPolicy.retention
        }
        for memo in expired { permanentlyDelete(memo) }
        return expired.count
    }

    /// Immediate hard delete of the SwiftData row only (callers clean up files
    /// themselves — MemoDetailView's delete path). Prefer `softDelete` for user
    /// deletes and `permanentlyDelete` when files should go too.
    func delete(_ memo: Memo) {
        context.delete(memo)
        save()
    }

    func save() {
        try? context.save()
    }
}
