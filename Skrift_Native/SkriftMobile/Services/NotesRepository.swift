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
        let schema = Schema([Memo.self, MemoAsset.self, NamesRecord.self, VocabularyRecord.self,
                             AudiobookSyncRecord.self, AudiobookAsset.self, MemoEnhancement.self,
                             PolishPromptsRecord.self])
        // CloudKit-backed (standalone Phase 1 internal sync): SwiftData mirrors the Memo
        // store to the user's PRIVATE CloudKit database, so notes sync across THEIR own
        // devices (iPhone↔iPad) with no Mac and no iCloud-Drive conflict-copy files.
        // Per-config container id matches the per-config entitlement (dev vs prod); the
        // container is registered once in Xcode → Signing & Capabilities. `MemoAsset`
        // (Phase 1c) carries the recording `.m4a` + photos as CloudKit-mirrored blobs so
        // the actual media crosses devices too, not just the Memo row.
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
    /// (`deletedAt != nil`), so every caller — list and search — automatically
    /// skips the trash.
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
    /// so Restore is lossless; the startup purge removes them once the purge
    /// clock (`trashSeenAt`, stamped here — a phone soft-delete only ever
    /// happens with the app open) has run `TrashPolicy.retention`. `date` is
    /// injectable for tests.
    func softDelete(_ memo: Memo, at date: Date = Date()) {
        DevLog.log("softDelete memo \(memo.id) status=\(memo.transcriptStatus) — caller: \(Self.callerFrames())")
        memo.deletedAt = date
        memo.trashSeenAt = date
        save()
    }

    /// A compact slice of the call stack above a delete, to pinpoint WHO triggered it
    /// during the 2026-06-21 "note vanished after append" hunt. If a memo disappears
    /// on device with NO `softDelete`/`delete`/`permanentlyDelete` line in devlog, the
    /// delete came from CloudKit's remote-change import, not our code. DEBUG/devlog-only.
    private static func callerFrames() -> String {
        Thread.callStackSymbols
            .dropFirst(2).prefix(4)
            .compactMap { line in line.split(separator: " ").dropFirst(3).first.map(String.init) }
            .joined(separator: " ← ")
    }

    /// Bring a trashed memo back to the main list, untouched.
    func restore(_ memo: Memo) {
        memo.deletedAt = nil
        memo.trashSeenAt = nil   // stale-stamp hygiene; the validity guard ignores it anyway
        save()
    }

    /// The full-delete path: removes the memo's audio, its photos, and the
    /// word-timings + diarization sidecars, then the row itself. Used by
    /// Delete-Now in Recently Deleted and the startup purge. (MemoDetailView's
    /// delete mirrors the same cleanup inline.)
    func permanentlyDelete(_ memo: Memo) {
        DevLog.log("permanentlyDelete memo \(memo.id) status=\(memo.transcriptStatus)")
        if let url = memo.audioURL { try? FileManager.default.removeItem(at: url) }
        if let fileURL = memo.sharedFileURL { try? FileManager.default.removeItem(at: fileURL) }
        memo.metadata?.imageManifest?.forEach {
            try? FileManager.default.removeItem(at: AppPaths.recordingsDirectory.appendingPathComponent($0.filename))
        }
        WordTimingsStore().delete(for: memo.id)
        DiarizationStore().delete(for: memo.id)
        // Drop the CloudKit-mirrored media blobs too (Phase 1c) — otherwise the
        // CKAssets outlive the memo and re-materialize orphaned audio on other devices.
        deleteAssets(forMemo: memo.id)
        context.delete(memo)
        save()
    }

    // MARK: - Media assets (CloudKit blobs — Phase 1c)

    /// Every `MemoAsset` row (audio + photo blobs across all memos).
    func allAssets() -> [MemoAsset] {
        (try? context.fetch(FetchDescriptor<MemoAsset>())) ?? []
    }

    /// The asset rows owned by one memo.
    func assets(forMemo id: UUID) -> [MemoAsset] {
        let descriptor = FetchDescriptor<MemoAsset>(predicate: #Predicate { $0.memoID == id })
        return (try? context.fetch(descriptor)) ?? []
    }

    /// The Mac's polish for a memo (the CloudKit write-back), or nil. App-level one-per-memo
    /// (reconciled by `memoID`); newest `enhancedAt` wins if two ever exist.
    func enhancement(forMemo id: UUID) -> MemoEnhancement? {
        let d = FetchDescriptor<MemoEnhancement>(predicate: #Predicate { $0.memoID == id })
        return (try? context.fetch(d))?.sorted { $0.enhancedAt > $1.enhancedAt }.first
    }

    /// Every Mac-polish enhancement (for a bulk scan — e.g. backlinks, which must look in the
    /// copyedit where a Mac-made memo-link lives, not just the raw transcript).
    func allEnhancements() -> [MemoEnhancement] {
        (try? context.fetch(FetchDescriptor<MemoEnhancement>())) ?? []
    }

    /// Delete a memo's asset rows. Caller saves (`permanentlyDelete` does).
    func deleteAssets(forMemo id: UUID) {
        for asset in assets(forMemo: id) { context.delete(asset) }
    }

    /// True when a synced `MemoAsset` exists for `filename` — i.e. the media is
    /// expected (downloading / pending materialization) even if its file isn't on
    /// disk yet. Drives the "Downloading from iCloud…" placeholder.
    /// Every tag across live memos, most-used first (the tag editor's
    /// autocomplete source).
    func allTags() -> [String] {
        var counts: [String: Int] = [:]
        for memo in allMemos() {
            for tag in memo.tags { counts[tag, default: 0] += 1 }
        }
        return counts.sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }.map(\.key)
    }

    func hasAsset(filename: String) -> Bool {
        guard !filename.isEmpty else { return false }
        var d = FetchDescriptor<MemoAsset>(predicate: #Predicate { $0.filename == filename })
        d.fetchLimit = 1
        return (try? context.fetchCount(d)) ?? 0 > 0
    }

    /// Every memo INCLUDING the trash — the asset-capture sweep mirrors files for
    /// trashed memos too (their files live on disk until the purge, and restore must
    /// be lossless across devices). Newest first, like `allMemos()`.
    func allMemosIncludingTrashed() -> [Memo] {
        let descriptor = FetchDescriptor<Memo>(
            sortBy: [SortDescriptor(\.recordedAt, order: .reverse)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    // MARK: - Names carrier (CloudKit sync — Phase 1e)

    /// The names-sync carrier rows. Normally 0 or 1; >1 only transiently when two
    /// devices each created one before syncing (`NamesCloudSync` collapses them).
    func allNamesRecords() -> [NamesRecord] {
        (try? context.fetch(FetchDescriptor<NamesRecord>())) ?? []
    }

    /// The custom-vocabulary carrier rows (Phase 1f). Normally 0 or 1;
    /// `VocabularyCloudSync` collapses any duplicates.
    func allVocabularyRecords() -> [VocabularyRecord] {
        (try? context.fetch(FetchDescriptor<VocabularyRecord>())) ?? []
    }

    func allPolishPromptsRecords() -> [PolishPromptsRecord] {
        (try? context.fetch(FetchDescriptor<PolishPromptsRecord>())) ?? []
    }

    // MARK: - Audiobook sync (per-book opt-in — Phase 1g/1h)

    /// Every opted-in audiobook's sync carrier.
    func allAudiobookRecords() -> [AudiobookSyncRecord] {
        (try? context.fetch(FetchDescriptor<AudiobookSyncRecord>())) ?? []
    }

    func audiobookRecord(bookID: UUID) -> AudiobookSyncRecord? {
        let d = FetchDescriptor<AudiobookSyncRecord>(predicate: #Predicate { $0.bookID == bookID })
        return try? context.fetch(d).first
    }

    func audiobookAssets(bookID: UUID) -> [AudiobookAsset] {
        let d = FetchDescriptor<AudiobookAsset>(predicate: #Predicate { $0.bookID == bookID })
        return (try? context.fetch(d)) ?? []
    }

    /// Stop syncing a book: drop its carrier + audio CKAssets (frees iCloud). Local
    /// audio files are left on disk by the caller (unshare keeps local copies).
    func deleteAudiobookSync(bookID: UUID) {
        audiobookRecord(bookID: bookID).map { context.delete($0) }
        for asset in audiobookAssets(bookID: bookID) { context.delete(asset) }
        save()
    }

    /// Startup purge: permanently delete every memo SEEN in the trash at least
    /// `TrashPolicy.retention` ago (inclusive) — `MemoLifecycle.purgeDue`, the
    /// v3 gate (2026-07-23). A trashed memo nobody has had the app open with
    /// (a `deletedAt` that synced in while the phone sat closed) never purges:
    /// the at-open stamp pass (`FadingSweep.run`) starts its clock instead, so
    /// this stays safe to run from `SkriftApp.init` on ANY process launch —
    /// background wakes included. `now` is injectable for tests.
    @discardableResult
    func purgeExpiredTrash(now: Date = Date()) -> Int {
        let expired = deletedMemos().filter { MemoLifecycle.purgeDue($0, now: now) }
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
        // The single persistence chokepoint for the notes store: a swallowed failure
        // here is indistinguishable from success, so retry once, then log loudly.
        do { try context.save() }
        catch {
            DevLog.log("save FAILED (retrying once): \(error)")
            do { try context.save() }
            catch { DevLog.log("save FAILED after retry — pending changes NOT persisted: \(error)") }
        }
    }
}
