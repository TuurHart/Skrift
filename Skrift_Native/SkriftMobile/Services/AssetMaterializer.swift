import Foundation
import SwiftData
import os

/// Bridges the CloudKit-mirrored `MemoAsset` blobs (Phase 1c) and the on-disk
/// files under `AppPaths.recordingsDirectory` that all the app's filename-based
/// code reads. Two idempotent directions, run together on launch + foreground:
///
/// - **materialize (import):** a `MemoAsset` synced from another device arrives as
///   a row + CKAsset; write its blob to `recordings/<filename>` so the recording
///   becomes playable/exportable here. This is the half that makes media actually
///   cross devices.
/// - **capture (export):** a memo's on-disk audio + photos get a matching
///   `MemoAsset` so CloudKit ships them out. Also MIGRATES pre-1c memos (files on
///   disk, no asset rows) and refreshes a stale asset after an append grew the audio.
///
/// Both run on the source device harmlessly (materialize skips files that exist;
/// capture skips assets that are up to date), so the same sweep is correct on every
/// device regardless of which way the data flows.
///
/// Q316: the sweep CORE is `nonisolated` and takes a `ModelContext`, so launch /
/// foreground / import-burst run it on `SweepActor`'s own context, off the main thread
/// (it is lstat- and blob-heavy: 1.4 s on the iPhone 13 with 2,000 notes). The
/// main-actor entry points below (`run`, `captureMissing(_ repository:)`,
/// `capture(memoID:)`) still run it on the main context, for the recording hot path and tests.
@MainActor
enum AssetMaterializer {

    /// Test-visible count of file stats the capture sweep made. Lets a test prove an
    /// unchanged store costs zero stats.
    nonisolated static var fileStatCount: Int { statCounter.withLock { $0 } }
    nonisolated static func resetFileStatCount() { statCounter.withLock { $0 = 0 } }
    private nonisolated static let statCounter = OSAllocatedUnfairLock(initialState: 0)

    /// How far back before the checkpoint a memo still counts as "changed". Sidecars
    /// (`wt_<id>.json` after a transcription, the diarization file after a speaker rename)
    /// are written AFTER the memo row, without necessarily touching `editedAt`; this window
    /// catches them on the next sweep. Anything older is covered by `fullSweepInterval`.
    nonisolated static let changedWindow: TimeInterval = 2 * 86_400
    /// Backstop: a full (un-checkpointed) capture pass at least this often.
    nonisolated static let fullSweepInterval: TimeInterval = 7 * 86_400

    /// recordings/<filename> — the canonical on-disk location for an asset.
    private nonisolated static func fileURL(_ filename: String) -> URL {
        AppPaths.recordingsDirectory.appendingPathComponent(filename)
    }

    /// Run both directions. Idempotent — safe on every launch + foreground.
    static func run(_ repository: NotesRepository) {
        materializeMissing(repository)
        captureMissing(repository)
    }

    // MARK: - Import direction (synced blob → disk)

    /// Write each `MemoAsset` whose target file is absent to `recordings/<filename>`.
    /// Never overwrites an existing file (the source device already has it, and a
    /// half-synced blob must not clobber a good local file).
    ///
    /// The fetch is METADATA-ONLY (`propertiesToFetch`): faulting is row-level, so a
    /// plain fetch realizes every multi-MB blob the moment ANY attribute is touched —
    /// the old "existence check runs before touching .blob" comment was wrong about
    /// that. With a scoped fetch, `.blob` faults in only for files actually written.
    static func materializeMissing(_ repository: NotesRepository) {
        materializeMissing(in: repository.context)
    }

    nonisolated static func materializeMissing(in context: ModelContext) {
        var descriptor = FetchDescriptor<MemoAsset>()
        descriptor.propertiesToFetch = [\.filename, \.kind, \.byteCount]
        for asset in (try? context.fetch(descriptor)) ?? [] where !asset.filename.isEmpty {
            let url = fileURL(asset.filename)
            guard !FileManager.default.fileExists(atPath: url.path) else { continue }
            do {
                try asset.blob.write(to: url, options: .atomic)
                DevLog.log("asset: materialized \(asset.kind) \(asset.filename) (\(asset.byteCount)B)")
            } catch {
                DevLog.log("asset: materialize FAILED \(asset.filename): \(error)")
            }
        }
    }

    // MARK: - Export direction (disk → synced blob)

    /// Ensure a (current) `MemoAsset` exists for every memo's on-disk audio + manifest
    /// photos. Creates missing assets (incl. migrating pre-1c memos), refreshes one
    /// whose file changed size (e.g. after an append). Trashed memos are included —
    /// their files live on disk until the purge and a cross-device restore must be
    /// lossless. Saves once if anything changed. (Main-context, every memo; the launch
    /// path uses `captureMissing(in:changedSince:)` on the background actor.)
    static func captureMissing(_ repository: NotesRepository) {
        if captureMissing(in: repository.context, changedSince: nil) { repository.save() }
    }

    /// The sweep core. `changedSince == nil` examines every memo (first run, the weekly
    /// backstop, the main-actor entry point); otherwise only memos recorded / created /
    /// edited after `changedSince - changedWindow`, so an unchanged store stats no files.
    /// With `saveBatches` it saves every 25 writes and at the end: a first run on a
    /// migrating library holds whole audio files as blobs, and one end-of-run save kept
    /// all of them in memory at once. Returns true if it created or refreshed an asset.
    @discardableResult
    nonisolated static func captureMissing(in context: ModelContext, changedSince: Date?,
                                           saveBatches: Bool = false) -> Bool {
        // R91/C278: scoped like `materializeMissing` above — a plain fetch faults
        // every asset's blob into memory (row-level faulting) the moment ANY field
        // is touched. This loop only ever reads `.filename`/`.byteCount`, so those
        // are the only columns fetched; over 200 notes' worth of assets, capturing
        // nothing touches zero blob bytes.
        var descriptor = FetchDescriptor<MemoAsset>()
        descriptor.propertiesToFetch = [\.filename, \.byteCount]
        let byFilename = indexByFilename((try? context.fetch(descriptor)) ?? [])
        var dirty = false
        var sinceSave = 0
        for memo in memosToExamine(in: context, changedSince: changedSince) {
            if captureFiles(of: memo, existing: byFilename, context: context) {
                dirty = true
                sinceSave += 1
                if saveBatches, sinceSave >= 25 {
                    try? context.save()
                    sinceSave = 0
                }
            }
        }
        if saveBatches, sinceSave > 0 { try? context.save() }
        return dirty
    }

    /// Every memo (trashed included — see above), or only the recently-changed ones.
    nonisolated static func memosToExamine(in context: ModelContext, changedSince: Date?) -> [Memo] {
        guard let changedSince else {
            return (try? context.fetch(FetchDescriptor<Memo>(
                sortBy: [SortDescriptor(\.recordedAt, order: .reverse)]))) ?? []
        }
        let since = changedSince.addingTimeInterval(-changedWindow)
        let never = Date.distantPast
        let descriptor = FetchDescriptor<Memo>(predicate: #Predicate<Memo> {
            $0.recordedAt > since
                || ($0.editedAt ?? never) > since
                || ($0.createdAt ?? never) > since
        })
        return (try? context.fetch(descriptor)) ?? []
    }

    /// Capture/refresh ONE memo's files immediately — used on the recording hot path
    /// (`MemoSaver.save`) so a fresh memo queues its blob for CloudKit without waiting
    /// for the next foreground sweep. Saves once if anything changed.
    static func capture(memoID: UUID, repository: NotesRepository) {
        guard let memo = repository.memo(id: memoID) else { return }
        let byFilename = indexByFilename(repository.assets(forMemo: memoID))
        if captureFiles(of: memo, existing: byFilename, context: repository.context) {
            repository.save()
        }
    }

    // MARK: - Internals

    private nonisolated static func indexByFilename(_ assets: [MemoAsset]) -> [String: MemoAsset] {
        // Filenames embed the memo UUID, so they're globally unique → last-wins is fine.
        Dictionary(assets.map { ($0.filename, $0) }, uniquingKeysWith: { _, b in b })
    }

    /// Returns true when it created or refreshed at least one asset (caller saves once).
    private nonisolated static func captureFiles(of memo: Memo, existing: [String: MemoAsset],
                                                 context: ModelContext) -> Bool {
        var dirty = false
        if captureFile(memo.audioFilename, kind: MemoAsset.Kind.audio, memoID: memo.id,
                       existing: existing, context: context) { dirty = true }
        for entry in memo.metadata?.imageManifest ?? [] {
            if captureFile(entry.filename, kind: MemoAsset.Kind.photo, memoID: memo.id,
                           existing: existing, context: context) { dirty = true }
        }
        // A shared `.file` capture's document (e.g. a PDF) → a document asset, so the actual
        // file reaches the Mac (3b), not just the text A6 already put in `sharedContent.text`.
        // C63 / C148 / D188: a video's source movie (<= 200 MB, `MemoSaver.keepMovie`) syncs
        // whatever the destination. Personal never goes to Claude, but it syncs through his own
        // iCloud like every other note; filing never deletes the blob. Only the PORTFOLIO export
        // copies the movie out (`ObsidianPublisher`).
        if let movie = memo.metadata?.videoFilename, !movie.isEmpty,
           captureFile(movie, kind: MemoAsset.Kind.video, memoID: memo.id,
                       existing: existing, context: context) { dirty = true }
        if let sc = memo.sharedContent, sc.type == .file, let rel = sc.filePath, !rel.isEmpty,
           captureFile(rel, kind: MemoAsset.Kind.document, memoID: memo.id,
                       existing: existing, context: context) { dirty = true }
        // A link capture's downloaded thumbnail → a thumbnail asset, so the Mac's card shows
        // it instead of the globe tile (Q260). Its own kind, never a photo (no manifest entry).
        if let thumb = MemoAsset.Kind.linkThumbnailFilename(memo.sharedContent),
           captureFile(thumb, kind: MemoAsset.Kind.thumbnail, memoID: memo.id,
                       existing: existing, context: context) { dirty = true }
        // Per-memo JSON sidecars (Phase 1d): word-timings (karaoke/read-along) +
        // diarization (speaker turns/names). Small, in the same recordings dir, keyed
        // by memo id. Absent on most memos → captureFile no-ops. byteCount staleness
        // also refreshes them after an append (new timings) or a speaker rename.
        if captureFile(WordTimingsStore.filename(for: memo.id), kind: MemoAsset.Kind.wordTimings,
                       memoID: memo.id, existing: existing, context: context) { dirty = true }
        if captureFile(DiarizationStore.filename(for: memo.id), kind: MemoAsset.Kind.diarization,
                       memoID: memo.id, existing: existing, context: context) { dirty = true }
        return dirty
    }

    /// Create the asset for `filename` if absent, or refresh its blob if the on-disk
    /// file changed size. No-op when the file isn't on disk (nothing to capture) or
    /// the asset is already current. Returns true on a create/refresh.
    private nonisolated static func captureFile(_ filename: String, kind: String, memoID: UUID,
                                                existing: [String: MemoAsset], context: ModelContext) -> Bool {
        guard !filename.isEmpty, let size = fileSize(fileURL(filename)) else { return false }
        if let asset = existing[filename] {
            guard asset.byteCount != size, let data = try? Data(contentsOf: fileURL(filename)) else { return false }
            asset.blob = data
            asset.byteCount = data.count
            DevLog.log("asset: refreshed \(kind) \(filename) (\(data.count)B)")
            return true
        }
        guard let data = try? Data(contentsOf: fileURL(filename)) else { return false }
        context.insert(MemoAsset(memoID: memoID, kind: kind, filename: filename, blob: data))
        DevLog.log("asset: captured \(kind) \(filename) (\(data.count)B)")
        return true
    }

    /// Plain `stat(2)`: `attributesOfItem` builds a whole attributes dictionary per call
    /// (637 ms of the 1.4 s sweep on the iPhone 13). nil = no such file.
    private nonisolated static func fileSize(_ url: URL) -> Int? {
        statCounter.withLock { $0 += 1 }
        var st = stat()
        guard stat(url.path, &st) == 0 else { return nil }
        return Int(st.st_size)
    }
}
