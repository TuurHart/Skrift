import Foundation
import SwiftData

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
/// device regardless of which way the data flows. Everything stays on the main actor
/// (SwiftData's context is main-actor-bound).
@MainActor
enum AssetMaterializer {

    /// recordings/<filename> — the canonical on-disk location for an asset.
    private static func fileURL(_ filename: String) -> URL {
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
        var descriptor = FetchDescriptor<MemoAsset>()
        descriptor.propertiesToFetch = [\.filename, \.kind, \.byteCount]
        for asset in (try? repository.context.fetch(descriptor)) ?? [] where !asset.filename.isEmpty {
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
    /// lossless. Saves once if anything changed.
    static func captureMissing(_ repository: NotesRepository) {
        let byFilename = indexByFilename(repository.allAssets())
        var dirty = false
        for memo in repository.allMemosIncludingTrashed() {
            if captureFiles(of: memo, existing: byFilename, repository: repository) { dirty = true }
        }
        if dirty { repository.save() }
    }

    /// Capture/refresh ONE memo's files immediately — used on the recording hot path
    /// (`MemoSaver.save`) so a fresh memo queues its blob for CloudKit without waiting
    /// for the next foreground sweep. Saves once if anything changed.
    static func capture(memoID: UUID, repository: NotesRepository) {
        guard let memo = repository.memo(id: memoID) else { return }
        let byFilename = indexByFilename(repository.assets(forMemo: memoID))
        if captureFiles(of: memo, existing: byFilename, repository: repository) {
            repository.save()
        }
    }

    // MARK: - Internals

    private static func indexByFilename(_ assets: [MemoAsset]) -> [String: MemoAsset] {
        // Filenames embed the memo UUID, so they're globally unique → last-wins is fine.
        Dictionary(assets.map { ($0.filename, $0) }, uniquingKeysWith: { _, b in b })
    }

    /// Returns true when it created or refreshed at least one asset (caller saves once).
    private static func captureFiles(of memo: Memo, existing: [String: MemoAsset],
                                     repository: NotesRepository) -> Bool {
        var dirty = false
        if captureFile(memo.audioFilename, kind: MemoAsset.Kind.audio, memoID: memo.id,
                       existing: existing, repository: repository) { dirty = true }
        for entry in memo.metadata?.imageManifest ?? [] {
            if captureFile(entry.filename, kind: MemoAsset.Kind.photo, memoID: memo.id,
                           existing: existing, repository: repository) { dirty = true }
        }
        // A shared `.file` capture's document (e.g. a PDF) → a document asset, so the actual
        // file reaches the Mac (3b), not just the text A6 already put in `sharedContent.text`.
        if let sc = memo.sharedContent, sc.type == .file, let rel = sc.filePath, !rel.isEmpty,
           captureFile(rel, kind: MemoAsset.Kind.document, memoID: memo.id,
                       existing: existing, repository: repository) { dirty = true }
        // Per-memo JSON sidecars (Phase 1d): word-timings (karaoke/read-along) +
        // diarization (speaker turns/names). Small, in the same recordings dir, keyed
        // by memo id. Absent on most memos → captureFile no-ops. byteCount staleness
        // also refreshes them after an append (new timings) or a speaker rename.
        if captureFile(WordTimingsStore.filename(for: memo.id), kind: MemoAsset.Kind.wordTimings,
                       memoID: memo.id, existing: existing, repository: repository) { dirty = true }
        if captureFile(DiarizationStore.filename(for: memo.id), kind: MemoAsset.Kind.diarization,
                       memoID: memo.id, existing: existing, repository: repository) { dirty = true }
        return dirty
    }

    /// Create the asset for `filename` if absent, or refresh its blob if the on-disk
    /// file changed size. No-op when the file isn't on disk (nothing to capture) or
    /// the asset is already current. Returns true on a create/refresh.
    private static func captureFile(_ filename: String, kind: String, memoID: UUID,
                                    existing: [String: MemoAsset], repository: NotesRepository) -> Bool {
        guard !filename.isEmpty, let size = fileSize(fileURL(filename)) else { return false }
        if let asset = existing[filename] {
            guard asset.byteCount != size, let data = try? Data(contentsOf: fileURL(filename)) else { return false }
            asset.blob = data
            asset.byteCount = data.count
            DevLog.log("asset: refreshed \(kind) \(filename) (\(data.count)B)")
            return true
        }
        guard let data = try? Data(contentsOf: fileURL(filename)) else { return false }
        repository.context.insert(MemoAsset(memoID: memoID, kind: kind, filename: filename, blob: data))
        DevLog.log("asset: captured \(kind) \(filename) (\(data.count)B)")
        return true
    }

    private static func fileSize(_ url: URL) -> Int? {
        (try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? Int
    }
}
