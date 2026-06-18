import Foundation
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

    // MARK: - Opt in / out (the "Sync this book" toggle calls these)

    /// Mark a book for cross-device sync. Idempotent. The audio upload happens in
    /// `reconcile` (the toggle calls `reconcile` right after); this shows immediate
    /// "Uploading…" feedback on the row.
    static func enableSync(book: Audiobook, repository: NotesRepository = .shared) {
        guard repository.audiobookRecord(bookID: book.id) == nil,
              let blob = try? JSONEncoder().encode(book) else { return }
        repository.context.insert(AudiobookSyncRecord(bookID: book.id, blob: blob))
        repository.save()
        CloudSyncMonitor.shared.setBookTransfer(book.id, direction: .up, fraction: 0)
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
            names = audioRecordNames(for: book)
        } else {
            names = []
        }
        repository.deleteAudiobookSync(bookID: bookID)   // drops carrier (+ any legacy AudiobookAsset rows)
        var s = removedDownloads(defaults); s.remove(bookID.uuidString)
        defaults.set(Array(s), forKey: removedDownloadsKey)
        CloudSyncMonitor.shared.clearBookTransfer(bookID)
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
        let folder = library.folder(for: bookID)
        let refs = audioRefs(for: book).filter {
            !FileManager.default.fileExists(atPath: folder.appendingPathComponent($0.filename).path)
        }
        guard !refs.isEmpty else { return }
        await downloadBook(book, refs: refs, folder: folder, transport: transport ?? makeTransport())
    }

    // MARK: - Reconcile (both directions, idempotent)

    static func reconcile(library: AudiobookLibraryStore = .shared, repository: NotesRepository = .shared,
                          defaults: UserDefaults = .standard, transport: AudiobookAudioTransport? = nil) async {
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
                // LWW by lastPlayedAt — adopt the remote resume position/rate if newer.
                if (remote.lastPlayedAt ?? .distantPast) > (local.lastPlayedAt ?? .distantPast) {
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
            }
        }

        // SEND: refresh each synced book's state blob if the local copy is newer, and
        // upload its audio ONCE (guarded by `audioUploadedAt`). A book present locally
        // but not yet uploaded is the source; a received phantom (audio absent) skips
        // upload because its files aren't on disk.
        for record in records {
            guard let local = library.book(id: record.bookID) else { continue }
            let recorded = try? JSONDecoder().decode(Audiobook.self, from: record.blob)
            if (local.lastPlayedAt ?? .distantPast) > (recorded?.lastPlayedAt ?? .distantPast),
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
                    await uploadBook(local, parts: parts, transport: transport, record: record, repository: repository)
                }
            }
        }
        repository.save()
    }

    // MARK: - Transfers (publish live progress to the row)

    private static func uploadBook(_ book: Audiobook, parts: [AudiobookAudioPart],
                                   transport: AudiobookAudioTransport, record: AudiobookSyncRecord,
                                   repository: NotesRepository) async {
        let bookID = book.id
        CloudSyncMonitor.shared.setBookTransfer(bookID, direction: .up, fraction: 0)
        do {
            try await transport.upload(parts) { fraction in
                Task { @MainActor in CloudSyncMonitor.shared.setBookTransfer(bookID, direction: .up, fraction: fraction) }
            }
            record.audioUploadedAt = Date()   // upload-once guard + receiver pull trigger
            repository.save()
        } catch {
            DevLog.log("audiobook upload failed \(bookID): \(error)")   // stays nil → retried next reconcile
        }
        CloudSyncMonitor.shared.clearBookTransfer(bookID)
    }

    private static func downloadBook(_ book: Audiobook, refs: [AudiobookAudioRef],
                                     folder: URL, transport: AudiobookAudioTransport) async {
        let bookID = book.id
        CloudSyncMonitor.shared.setBookTransfer(bookID, direction: .down, fraction: 0)
        do {
            try await transport.download(refs, into: folder) { fraction in
                Task { @MainActor in CloudSyncMonitor.shared.setBookTransfer(bookID, direction: .down, fraction: fraction) }
            }
        } catch {
            DevLog.log("audiobook download failed \(bookID): \(error)")
        }
        CloudSyncMonitor.shared.clearBookTransfer(bookID)
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
}
