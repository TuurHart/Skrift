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
        // CloudKit-backed (standalone Phase 1 internal sync): SwiftData mirrors the Memo
        // store to the user's PRIVATE CloudKit database, so notes sync across THEIR own
        // devices (iPhone↔iPad) with no Mac and no iCloud-Drive conflict-copy files.
        // Per-config container id matches the per-config entitlement (dev vs prod); the
        // container is registered once in Xcode → Signing & Capabilities. Audio/photos
        // stay device-local in this chunk (the Memo ROW syncs); CKAsset media sync is next.
        //
        // CloudKit is forced OFF for the in-memory path AND under XCTest, so the UI/unit
        // suites stay offline + deterministic and never touch a CloudKit container.
        #if DEBUG
        let cloudContainer = "iCloud.com.skrift.mobile.dev"
        #else
        let cloudContainer = "iCloud.com.skrift.mobile"
        #endif
        let isTesting = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        let cloudKit: ModelConfiguration.CloudKitDatabase = (inMemory || isTesting)
            ? .none : .private(cloudContainer)
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory,
                                        cloudKitDatabase: cloudKit)
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
        DevLog.log("softDelete memo \(memo.id) status=\(memo.transcriptStatus)")
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
        DevLog.log("permanentlyDelete memo \(memo.id) status=\(memo.transcriptStatus)")
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
        DevLog.log("delete(row) memo \(memo.id) status=\(memo.transcriptStatus)")
        context.delete(memo)
        save()
    }

    func save() {
        try? context.save()
    }
}
