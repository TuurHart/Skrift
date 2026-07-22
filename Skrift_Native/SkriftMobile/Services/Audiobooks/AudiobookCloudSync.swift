import Foundation
import CloudKit
import SwiftData

/// Per-book audiobook sync (standalone Phase 1g/1h). Books are local-only by
/// default; opting one in creates an `AudiobookSyncRecord` (its state, on SwiftData/
/// CloudKit) and transfers its audio via the raw-CloudKit `AudiobookAudioTransport`
/// (NOT a SwiftData blob) so the per-book bar shows a REAL upload/download %. Reconciles
/// AGAINST the existing `AudiobookLibraryStore` (`library.json`) — the library + player
/// code is untouched, same overlay approach as names/vocab.
///
/// State (position/rate/lastPlayedAt) rides the SwiftData carrier and LWWs by
/// `lastPlayedAt`. Audio rides raw CloudKit, gated by `audioUploadedAt`: the source
/// uploads once + stamps it (which pushes the carrier → nudges the receiver to fetch).
///
/// NOTE: the opt-in/out + reconcile are callable; `reconcile` is wired into the
/// launch/foreground/import/pull-to-refresh sweeps. With no synced book it's fully
/// inert (returns before constructing any CloudKit transport → no surprise uploads).
@MainActor
enum AudiobookCloudSync {

    /// Per-config private CloudKit container (matches the entitlement + the Memo store).
    static var containerID: String {
        #if DEBUG
        "iCloud.com.skrift.mobile.dev"
        #else
        "iCloud.com.skrift.mobile"
        #endif
    }

    private static func makeTransport() -> AudiobookAudioTransport {
        CloudKitAudiobookTransport(containerID: containerID)
    }

    // MARK: - CKError-aware retry policy

    /// Transient-failure cooldowns (zone busy / rate limited / no network):
    /// retried automatically, but not before this date — the server's own
    /// `retryAfterSeconds` when it sent one. In-memory; a relaunch retries.
    private static var cooldownUntil: [UUID: Date] = [:]

    /// Classify a transfer failure. Transient → cooldown; permanent (iCloud
    /// full, signed out) → auto-retry stops and the sync sheet shows why
    /// (previously EVERY failure was DevLog-only and retried forever).
    private static func noteFailure(_ error: Error, book bookID: UUID, op: String) {
        guard let ck = error as? CKError else {
            DevLog.log("audiobook \(op) failed \(bookID): \(error)")   // unknown → retried next reconcile
            return
        }
        switch ck.code {
        case .zoneBusy, .requestRateLimited, .serviceUnavailable, .networkUnavailable, .networkFailure:
            let delay = ck.retryAfterSeconds ?? 60
            cooldownUntil[bookID] = Date().addingTimeInterval(delay)
            DevLog.log("audiobook \(op) transient CKError \(ck.code.rawValue) \(bookID) — cooldown \(Int(delay))s")
        case .quotaExceeded:
            CloudSyncMonitor.shared.setBookSyncFailure(bookID, reason: "iCloud storage is full — sync paused for this book.")
            DevLog.log("audiobook \(op) PERMANENT (quotaExceeded) \(bookID) — auto-retry stopped")
        case .notAuthenticated:
            CloudSyncMonitor.shared.setBookSyncFailure(bookID, reason: "Not signed in to iCloud — sync paused for this book.")
            DevLog.log("audiobook \(op) PERMANENT (notAuthenticated) \(bookID) — auto-retry stopped")
        default:
            DevLog.log("audiobook \(op) failed CKError \(ck.code.rawValue) \(bookID): \(error)")
        }
    }

    /// One choke point for every transfer entry: paused-permanent or cooling-down
    /// books skip the raw-CloudKit ops (state-blob sync via SwiftData continues).
    private static func transfersPaused(for bookID: UUID) -> Bool {
        if CloudSyncMonitor.shared.bookSyncFailures[bookID] != nil { return true }
        if let until = cooldownUntil[bookID] {
            if until > Date() { return true }
            cooldownUntil[bookID] = nil
        }
        return false
    }

    // MARK: - Opt in / out (the "Sync this book" toggle calls these)

    /// Mark a book for cross-device sync. Idempotent. The audio upload happens in
    /// `reconcile` (the toggle calls `reconcile` right after); this shows immediate
    /// "Uploading…" feedback on the row.
    static func enableSync(book: Audiobook, repository: NotesRepository = .shared) {
        guard repository.audiobookRecord(bookID: book.id) == nil,
              let blob = try? JSONEncoder().encode(book) else { return }
        repository.context.insert(AudiobookSyncRecord(bookID: book.id, blob: blob))
        repository.save()
        _ = CloudSyncMonitor.shared.beginBookTransfer(book.id, direction: .up)   // immediate feedback until reconcile's upload starts
    }

    /// Stop syncing (unshare): drop the carrier + delete the CloudKit audio records —
    /// frees iCloud. Every device keeps the audio it already downloaded (the file stays
    /// on disk; the book reverts to local-only). Async so the cloud delete is awaited
    /// (UI handlers wrap in a Task).
    static func disableSync(bookID: UUID, repository: NotesRepository = .shared,
                            defaults: UserDefaults = .standard,
                            transport: AudiobookAudioTransport? = nil) async {
        let names: [String]
        if let record = repository.audiobookRecord(bookID: bookID),
           let book = try? JSONDecoder().decode(Audiobook.self, from: record.blob) {
            names = audioRecordNames(for: book) + transcriptRecordNames(for: book) + alignmentRecordNames(for: book)
        } else {
            names = []
        }
        repository.deleteAudiobookSync(bookID: bookID)   // drops carrier (+ any legacy AudiobookAsset rows)
        var s = removedDownloads(defaults); s.remove(bookID.uuidString)
        defaults.set(Array(s), forKey: removedDownloadsKey)
        defaults.removeObject(forKey: transcriptAppliedKey(bookID))   // re-pull transcripts if re-synced later
        defaults.removeObject(forKey: alignmentAppliedKey(bookID))    // 📖 re-pull alignment if re-synced later
        CloudSyncMonitor.shared.cancelBookTransfer(bookID)   // supersede any in-flight transfer's late callbacks
        if !names.isEmpty {
            let t = transport ?? makeTransport()
            try? await t.delete(recordNames: names)
        }
    }

    /// A book is "synced" exactly when a carrier exists — the toggle's state, no flag.
    static func isSynced(bookID: UUID, repository: NotesRepository = .shared) -> Bool {
        repository.audiobookRecord(bookID: bookID) != nil
    }

    // MARK: - Per-device "Remove download" (Apple Books model)

    /// Books whose audio the user freed on THIS device — a per-device choice, NOT
    /// synced. They stay synced (the record is kept) but won't auto-redownload here
    /// until asked, so you can reclaim space on one device without unsharing.
    private static let removedDownloadsKey = "audiobookRemovedDownloads"

    static func removedDownloads(_ defaults: UserDefaults = .standard) -> Set<String> {
        Set((defaults.array(forKey: removedDownloadsKey) as? [String]) ?? [])
    }

    static func isDownloadRemoved(bookID: UUID, defaults: UserDefaults = .standard) -> Bool {
        removedDownloads(defaults).contains(bookID.uuidString)
    }

    /// Free a SYNCED book's local audio on this device (keeps the record → still synced,
    /// re-downloadable). Guarded to synced books so it can never delete a local-only
    /// book's only copy. The cloud records stay (re-downloadable).
    static func removeDownload(bookID: UUID, library: AudiobookLibraryStore = .shared,
                               repository: NotesRepository = .shared, defaults: UserDefaults = .standard) {
        guard isSynced(bookID: bookID, repository: repository) else { return }
        // Supersede any in-flight download's late callbacks (same reason disableSync
        // does) so a pull racing this can't re-materialize the files we just freed.
        CloudSyncMonitor.shared.cancelBookTransfer(bookID)
        if let book = library.book(id: bookID) {
            let folder = library.folder(for: bookID)
            for name in syncedFilenames(book) {
                try? FileManager.default.removeItem(at: folder.appendingPathComponent(name))
            }
        }
        var s = removedDownloads(defaults); s.insert(bookID.uuidString)
        defaults.set(Array(s), forKey: removedDownloadsKey)
    }

    /// Re-download a freed book on this device: clear the marker + fetch the audio now.
    static func restoreDownload(bookID: UUID, library: AudiobookLibraryStore = .shared,
                                repository: NotesRepository = .shared, defaults: UserDefaults = .standard,
                                transport: AudiobookAudioTransport? = nil) async {
        var s = removedDownloads(defaults); s.remove(bookID.uuidString)
        defaults.set(Array(s), forKey: removedDownloadsKey)
        guard let record = repository.audiobookRecord(bookID: bookID),
              let book = try? JSONDecoder().decode(Audiobook.self, from: record.blob) else { return }
        let t = transport ?? makeTransport()
        let folder = library.folder(for: bookID)
        let refs = audioRefs(for: book).filter {
            !FileManager.default.fileExists(atPath: folder.appendingPathComponent($0.filename).path)
        }
        if !refs.isEmpty {
            await downloadBook(book, refs: refs, folder: folder, transport: t)
        }
        // Re-downloaded audio has a new mtime → re-pull + re-stamp the transcripts so
        // read-along works again here (force it past the applied-signature guard).
        defaults.removeObject(forKey: transcriptAppliedKey(bookID))
        await receiveTranscripts(book, record: record, folder: folder, transport: t,
                                 defaults: defaults, library: library)
    }

    // MARK: - Reconcile (both directions, idempotent)

    /// Single-flight guard. `reconcile` fires from ≥5 places (launch, foreground,
    /// pull-to-refresh, import-done, the toggle); each is async + suspends at every
    /// upload/download `await`, so without this two runs could interleave and
    /// double-upload the same book or race the carrier writes. Concurrent callers
    /// coalesce into one trailing re-run (picking up the latest store state).
    private static var isReconciling = false
    private static var rerunRequested = false

    static func reconcile(library: AudiobookLibraryStore = .shared, repository: NotesRepository = .shared,
                          defaults: UserDefaults = .standard, transport: AudiobookAudioTransport? = nil) async {
        if isReconciling { rerunRequested = true; return }
        isReconciling = true
        defer { isReconciling = false }
        repeat {
            rerunRequested = false
            await reconcileOnce(library: library, repository: repository, defaults: defaults, transport: transport)
        } while rerunRequested
    }

    private static func reconcileOnce(library: AudiobookLibraryStore, repository: NotesRepository,
                                      defaults: UserDefaults, transport: AudiobookAudioTransport?) async {
        let records = repository.allAudiobookRecords()
        guard !records.isEmpty else { return }   // nothing synced → fully inert (no CloudKit touched)
        let transport = transport ?? makeTransport()
        let removed = removedDownloads(defaults)

        // RECEIVE: each synced record → ensure a local entry (so the book shows even
        // before audio lands), and pull its audio (unless its download was freed here)
        // once the source has stamped `audioUploadedAt`.
        for record in records {
            guard let remote = try? JSONDecoder().decode(Audiobook.self, from: record.blob) else { continue }
            if let local = library.book(id: remote.id) {
                // LWW by modifiedAt — adopt the remote position/rate/etc. if newer.
                // (modifiedAt, not lastPlayedAt, so a speed-only change also wins.)
                if remote.modifiedAt > local.modifiedAt {
                    library.update(remote)
                }
            } else {
                library.add(remote)   // receiver: the book appears (audio materializes below)
            }
            if record.audioUploadedAt != nil, !removed.contains(remote.id.uuidString) {
                let folder = library.folder(for: remote.id)
                let missing = audioRefs(for: remote).filter {
                    !FileManager.default.fileExists(atPath: folder.appendingPathComponent($0.filename).path)
                }
                if !missing.isEmpty {
                    await downloadBook(remote, refs: missing, folder: folder, transport: transport)
                }
                // Read-along transcript sidecars (once the audio is present to re-stamp against).
                await receiveTranscripts(remote, record: record, folder: folder,
                                         transport: transport, defaults: defaults, library: library)
                // 📖 spike 6: alignment sidecars (chapter marks derive once they're fresh
                // against whatever transcript just landed above).
                await receiveAlignments(remote, record: record, folder: folder,
                                        transport: transport, defaults: defaults, library: library)
            }
        }

        // SEND: refresh each synced book's state blob if the local copy is newer, and
        // upload its audio ONCE (guarded by `audioUploadedAt`). A book present locally
        // but not yet uploaded is the source; a received phantom (audio absent) skips
        // upload because its files aren't on disk.
        for record in records {
            guard let local = library.book(id: record.bookID) else { continue }
            let recorded = try? JSONDecoder().decode(Audiobook.self, from: record.blob)
            if local.modifiedAt > (recorded?.modifiedAt ?? .distantPast),
               let blob = try? JSONEncoder().encode(local) {
                record.blob = blob
                record.modifiedAt = Date()
            }
            if record.audioUploadedAt == nil {
                let folder = library.folder(for: local.id)
                let parts = audioParts(for: local, folder: folder).filter {
                    FileManager.default.fileExists(atPath: $0.fileURL.path)
                }
                if !parts.isEmpty {
                    await uploadBook(local, parts: parts, transport: transport, repository: repository)
                }
            }
            // Upload the read-along transcript sidecars when they exist + changed (so a
            // book transcribed AFTER it was synced still propagates — not gated by the
            // audio upload-once).
            await sendTranscripts(local, record: record, library: library, transport: transport)
            // 📖 spike 6: same for alignment sidecars — also ungated by the audio upload-once.
            await sendAlignments(local, record: record, library: library, transport: transport)
        }
        repository.save()
    }

    // MARK: - Transfers (publish live progress to the row)

    private static func uploadBook(_ book: Audiobook, parts: [AudiobookAudioPart],
                                   transport: AudiobookAudioTransport, repository: NotesRepository) async {
        let bookID = book.id
        if transfersPaused(for: bookID) { return }
        let epoch = CloudSyncMonitor.shared.beginBookTransfer(bookID, direction: .up)
        do {
            try await transport.upload(parts) { fraction in
                Task { @MainActor in CloudSyncMonitor.shared.updateBookTransfer(bookID, epoch: epoch, fraction: fraction) }
            }
            // Re-fetch the carrier AFTER the await: the user may have hit "Stop syncing"
            // mid-upload, which deletes it — writing the captured (now-deleted) @Model
            // would trap. If it's gone, the unshare wins; just drop the stamp.
            if let live = repository.audiobookRecord(bookID: bookID) {
                live.audioUploadedAt = Date()   // upload-once guard + receiver pull trigger
                repository.save()
            }
        } catch {
            noteFailure(error, book: bookID, op: "upload")   // stamp stays nil → retried per policy
        }
        CloudSyncMonitor.shared.endBookTransfer(bookID, epoch: epoch)
    }

    private static func downloadBook(_ book: Audiobook, refs: [AudiobookAudioRef],
                                     folder: URL, transport: AudiobookAudioTransport) async {
        let bookID = book.id
        if transfersPaused(for: bookID) { return }
        let epoch = CloudSyncMonitor.shared.beginBookTransfer(bookID, direction: .down)
        do {
            try await transport.download(refs, into: folder) { fraction in
                Task { @MainActor in CloudSyncMonitor.shared.updateBookTransfer(bookID, epoch: epoch, fraction: fraction) }
            }
        } catch {
            noteFailure(error, book: bookID, op: "download")
        }
        // The cover file may have just landed — drop its cached placeholder so the row
        // redraws the real art (the cache never stores nil, so this only matters for a
        // re-download, but it's cheap insurance). endBookTransfer's publish re-renders.
        BookCoverCache.invalidate(bookID)
        CloudSyncMonitor.shared.endBookTransfer(bookID, epoch: epoch)
    }

    // MARK: - Sizes (local files — the size sheet + Settings "Synced audiobooks")

    /// On-device size of a book's audio (sum of its files + cover) — CloudKit doesn't
    /// expose the iCloud quota, so we report OUR local footprint.
    static func localSize(of book: Audiobook, library: AudiobookLibraryStore = .shared) -> Int {
        let folder = library.folder(for: book.id)
        return syncedFilenames(book).reduce(0) { acc, name in
            let attrs = try? FileManager.default.attributesOfItem(atPath: folder.appendingPathComponent(name).path)
            return acc + ((attrs?[.size] as? Int) ?? 0)
        }
    }

    // MARK: - Record addressing (stable, ASCII, slash-free)

    /// The files a synced book carries: its audio parts + `cover.jpg` when present.
    private static func syncedFilenames(_ book: Audiobook) -> [String] {
        book.files + (book.hasCover ? ["cover.jpg"] : [])
    }

    /// `ab_<bookID>_<index>` per audio file (`_cover` for the cover) — index-based, NOT
    /// the raw filename, so it stays ASCII / slash-free / no leading `_` (CloudKit's
    /// only documented recordName rules). Both devices derive these identically from
    /// the synced `files` order, so the receiver fetches by exact id.
    private static func recordName(bookID: UUID, index: Int) -> String { "ab_\(bookID.uuidString)_\(index)" }
    private static func coverRecordName(_ bookID: UUID) -> String { "ab_\(bookID.uuidString)_cover" }

    private static func audioRecordNames(for book: Audiobook) -> [String] {
        var names = book.files.indices.map { recordName(bookID: book.id, index: $0) }
        if book.hasCover { names.append(coverRecordName(book.id)) }
        return names
    }

    private static func audioParts(for book: Audiobook, folder: URL) -> [AudiobookAudioPart] {
        var parts = book.files.enumerated().map { index, name in
            AudiobookAudioPart(recordName: recordName(bookID: book.id, index: index),
                               filename: name, fileURL: folder.appendingPathComponent(name))
        }
        if book.hasCover {
            parts.append(AudiobookAudioPart(recordName: coverRecordName(book.id),
                                            filename: "cover.jpg", fileURL: folder.appendingPathComponent("cover.jpg")))
        }
        return parts
    }

    private static func audioRefs(for book: Audiobook) -> [AudiobookAudioRef] {
        var refs = book.files.enumerated().map { index, name in
            AudiobookAudioRef(recordName: recordName(bookID: book.id, index: index), filename: name)
        }
        if book.hasCover {
            refs.append(AudiobookAudioRef(recordName: coverRecordName(book.id), filename: "cover.jpg"))
        }
        return refs
    }

    // MARK: - Read-along transcript sidecars (synced separately from the audio)

    private static func transcriptRecordName(bookID: UUID, index: Int) -> String { "ab_\(bookID.uuidString)_t\(index)" }
    private static func transcriptFilename(_ index: Int) -> String { "transcript_f\(index).json" }
    private static func transcriptRecordNames(for book: Audiobook) -> [String] {
        book.files.indices.map { transcriptRecordName(bookID: book.id, index: $0) }
    }

    /// Content signature of the local (staleness-valid) transcript sidecars —
    /// `"<i>:<coveredUpTo>:<wordCount>"` joined. Excludes the per-file staleness key so
    /// the source and a re-stamped receiver compute the SAME value (no upload churn).
    private static func localTranscriptSignature(_ book: Audiobook, library: AudiobookLibraryStore) -> String {
        let store = BookTranscriptStore(directory: library.directory)
        let folder = library.folder(for: book.id)
        var parts: [String] = []
        for (i, name) in book.files.enumerated() {
            // frontierStats = the two scalars this signature needs, cache-served —
            // this used to full-decode every sidecar per reconcile, on main.
            let sig = store.signature(forFileAt: folder.appendingPathComponent(name))
            if let stats = store.frontierStats(bookID: book.id, fileIndex: i, expectedSignature: sig) {
                parts.append("\(i):\(Int(stats.covered)):\(stats.wordCount)")
            }
        }
        return parts.joined(separator: "|")
    }

    private static func transcriptParts(for book: Audiobook, folder: URL) -> [AudiobookAudioPart] {
        book.files.indices.compactMap { i in
            let url = folder.appendingPathComponent(transcriptFilename(i))
            guard FileManager.default.fileExists(atPath: url.path) else { return nil }
            return AudiobookAudioPart(recordName: transcriptRecordName(bookID: book.id, index: i),
                                      filename: transcriptFilename(i), fileURL: url)
        }
    }

    private static func transcriptRefs(for book: Audiobook) -> [AudiobookAudioRef] {
        book.files.indices.map { i in
            AudiobookAudioRef(recordName: transcriptRecordName(bookID: book.id, index: i),
                              filename: transcriptFilename(i))
        }
    }

    /// SOURCE: upload the transcript sidecars when they exist + changed since the
    /// carrier's recorded signature (tiny JSON → no progress UI).
    private static func sendTranscripts(_ book: Audiobook, record: AudiobookSyncRecord,
                                        library: AudiobookLibraryStore, transport: AudiobookAudioTransport) async {
        let sig = localTranscriptSignature(book, library: library)
        guard !sig.isEmpty, sig != record.transcriptSignature else { return }
        let folder = library.folder(for: book.id)
        let parts = transcriptParts(for: book, folder: folder)
        guard !parts.isEmpty else { return }
        do {
            try await transport.upload(parts) { _ in }
            record.transcriptSignature = sig
        } catch {
            DevLog.log("audiobook transcript upload failed \(book.id): \(error)")
        }
    }

    /// RECEIVER: pull the transcript sidecars when the carrier's signature is new to
    /// THIS device, then re-stamp them to the local audio (mtime differs after
    /// download, so `BookTranscriptStore.load` would otherwise reject them as stale).
    private static func receiveTranscripts(_ book: Audiobook, record: AudiobookSyncRecord, folder: URL,
                                           transport: AudiobookAudioTransport, defaults: UserDefaults,
                                           library: AudiobookLibraryStore) async {
        guard !record.transcriptSignature.isEmpty else { return }
        // Re-stamping needs the audio present (its signature is the new staleness key).
        let audioPresent = !book.files.isEmpty && book.files.allSatisfy {
            FileManager.default.fileExists(atPath: folder.appendingPathComponent($0).path)
        }
        guard audioPresent else { return }
        let appliedKey = transcriptAppliedKey(book.id)
        guard defaults.string(forKey: appliedKey) != record.transcriptSignature else { return }
        try? await transport.download(transcriptRefs(for: book), into: folder) { _ in }
        restampTranscripts(book, library: library)
        defaults.set(record.transcriptSignature, forKey: appliedKey)
    }

    private static func transcriptAppliedKey(_ bookID: UUID) -> String {
        "audiobookTranscriptApplied.\(bookID.uuidString)"
    }

    /// Re-key each downloaded sidecar to THIS device's audio signature so it passes the
    /// staleness check. No-op on the source (its sidecar already matches its audio).
    private static func restampTranscripts(_ book: Audiobook, library: AudiobookLibraryStore) {
        let store = BookTranscriptStore(directory: library.directory)
        let folder = library.folder(for: book.id)
        for (i, name) in book.files.enumerated() {
            let sig = store.signature(forFileAt: folder.appendingPathComponent(name))
            guard !sig.isEmpty else { continue }
            let sidecar = store.sidecarURL(bookID: book.id, fileIndex: i)
            guard let data = try? Data(contentsOf: sidecar),
                  var ft = try? JSONDecoder().decode(FileTranscript.self, from: data),
                  ft.signature != sig else { continue }
            ft.signature = sig
            try? store.save(ft, bookID: book.id)
        }
    }

    // MARK: - Alignment sidecars (📖 spike 6 — synced like transcripts, never restamped)

    private static func alignmentRecordName(bookID: UUID, index: Int) -> String { "ab_\(bookID.uuidString)_al\(index)" }
    private static func alignmentFilename(_ index: Int) -> String { "alignment_f\(index).json" }
    private static func alignmentRecordNames(for book: Audiobook) -> [String] {
        book.files.indices.map { alignmentRecordName(bookID: book.id, index: $0) }
    }

    /// Content signature of the local alignment sidecars — `FileAlignment.cloudSignaturePart()`
    /// joined with "|", mirroring `localTranscriptSignature`'s shape exactly.
    private static func localAlignmentSignature(_ book: Audiobook, library: AudiobookLibraryStore) -> String {
        let store = BookAlignmentStore(directory: library.directory)
        var parts: [String] = []
        for i in book.files.indices {
            if let fa = store.fileAlignment(bookID: book.id, fileIndex: i) {
                parts.append(fa.cloudSignaturePart())
            }
        }
        return parts.joined(separator: "|")
    }

    private static func alignmentParts(for book: Audiobook, folder: URL) -> [AudiobookAudioPart] {
        book.files.indices.compactMap { i in
            let url = folder.appendingPathComponent(alignmentFilename(i))
            guard FileManager.default.fileExists(atPath: url.path) else { return nil }
            return AudiobookAudioPart(recordName: alignmentRecordName(bookID: book.id, index: i),
                                      filename: alignmentFilename(i), fileURL: url)
        }
    }

    private static func alignmentRefs(for book: Audiobook) -> [AudiobookAudioRef] {
        book.files.indices.map { i in
            AudiobookAudioRef(recordName: alignmentRecordName(bookID: book.id, index: i),
                              filename: alignmentFilename(i))
        }
    }

    /// SOURCE: upload the alignment sidecars when they exist + changed since the carrier's
    /// recorded signature (tiny JSON → no progress UI) — mirrors `sendTranscripts`.
    private static func sendAlignments(_ book: Audiobook, record: AudiobookSyncRecord,
                                       library: AudiobookLibraryStore, transport: AudiobookAudioTransport) async {
        let sig = localAlignmentSignature(book, library: library)
        guard !sig.isEmpty, sig != record.alignmentSignature else { return }
        let folder = library.folder(for: book.id)
        let parts = alignmentParts(for: book, folder: folder)
        guard !parts.isEmpty else { return }
        do {
            try await transport.upload(parts) { _ in }
            record.alignmentSignature = sig
        } catch {
            DevLog.log("audiobook alignment upload failed \(book.id): \(error)")
        }
    }

    private static func alignmentAppliedKey(_ bookID: UUID) -> String {
        "audiobookAlignmentApplied.\(bookID.uuidString)"
    }

    /// RECEIVER: pull the alignment sidecars when the carrier's signature is new to THIS
    /// device. UNLIKE transcripts, alignment sidecars are NEVER restamped — they key off
    /// TRANSCRIPT CONTENT, not audio mtime — so the applied-key (→ `epubChapters` derived) only
    /// gets set once every file whose sidecar landed is `isFresh` against THIS device's own
    /// transcript sidecar. A receiver has no ePub to re-align locally, so a mismatch just holds;
    /// the unset key makes the next reconcile retry for the cost of a small re-download.
    private static func receiveAlignments(_ book: Audiobook, record: AudiobookSyncRecord, folder: URL,
                                          transport: AudiobookAudioTransport, defaults: UserDefaults,
                                          library: AudiobookLibraryStore) async {
        guard !record.alignmentSignature.isEmpty else { return }
        let appliedKey = alignmentAppliedKey(book.id)
        guard defaults.string(forKey: appliedKey) != record.alignmentSignature else { return }
        try? await transport.download(alignmentRefs(for: book), into: folder) { _ in }

        let store = BookAlignmentStore(directory: library.directory)
        let fileAlignments = book.files.indices.map { store.fileAlignment(bookID: book.id, fileIndex: $0) }
        let allFresh = zip(book.files.indices, fileAlignments).allSatisfy { i, fa in
            guard let fa else { return true }   // nothing landed for this file yet — not a blocker
            return store.isFresh(fa, bookID: book.id, fileIndex: i,
                                 audioURL: folder.appendingPathComponent(book.files[i]))
        }
        guard allFresh else { return }

        let chapters = BookAlignmentRunner.epubChapters(from: fileAlignments, fileStartTimes: book.fileStartTimes,
                                                         bookDuration: book.duration)
        if !chapters.isEmpty, var fresh = library.book(id: book.id) {
            fresh.epubChapters = chapters
            library.update(fresh)
        }
        defaults.set(record.alignmentSignature, forKey: appliedKey)
    }
}
