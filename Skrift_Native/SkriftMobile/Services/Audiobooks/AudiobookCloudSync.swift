import Foundation
import SwiftData

/// Per-book audiobook sync (standalone Phase 1g/1h). Books are local-only by
/// default; opting one in creates an `AudiobookSyncRecord` (its state) + uploads its
/// audio as `AudiobookAsset` CKAssets, so it appears + resumes on the user's other
/// devices. Reconciles AGAINST the existing `AudiobookLibraryStore` (`library.json`)
/// — the library + player code is untouched, same overlay approach as names/vocab.
///
/// NOTE: the opt-in/out API + reconcile are callable but NOT auto-wired yet — the
/// toggle UI + the Wi-Fi/cellular upload policy land in the next sub-chunk. Until
/// then no book is synced, so this is inert (and safe: no surprise uploads).
@MainActor
enum AudiobookCloudSync {

    // MARK: - Opt in / out (the "Sync this book" toggle calls these)

    /// Mark a book for cross-device sync. Idempotent. Audio upload happens in
    /// `reconcile` (capture), gated by network policy there (added with the UI).
    static func enableSync(book: Audiobook, repository: NotesRepository = .shared) {
        guard repository.audiobookRecord(bookID: book.id) == nil,
              let blob = try? JSONEncoder().encode(book) else { return }
        repository.context.insert(AudiobookSyncRecord(bookID: book.id, blob: blob))
        repository.save()
    }

    /// Stop syncing (unshare): drop the carrier + CKAssets — frees iCloud. Every
    /// device keeps the audio it already downloaded (the file stays on disk; the book
    /// reverts to local-only).
    static func disableSync(bookID: UUID, repository: NotesRepository = .shared) {
        repository.deleteAudiobookSync(bookID: bookID)
    }

    /// A book is "synced" exactly when a carrier exists — the toggle's state, no flag.
    static func isSynced(bookID: UUID, repository: NotesRepository = .shared) -> Bool {
        repository.audiobookRecord(bookID: bookID) != nil
    }

    // MARK: - Reconcile (both directions, idempotent)

    static func reconcile(library: AudiobookLibraryStore = .shared, repository: NotesRepository = .shared) {
        // RECEIVE: each synced record → materialize its audio + ensure a local entry.
        for record in repository.allAudiobookRecords() {
            guard let remote = try? JSONDecoder().decode(Audiobook.self, from: record.blob) else { continue }
            materializeAudio(bookID: remote.id, library: library, repository: repository)
            if let local = library.book(id: remote.id) {
                // LWW by lastPlayedAt — adopt the remote resume position/rate if newer.
                if (remote.lastPlayedAt ?? .distantPast) > (local.lastPlayedAt ?? .distantPast) {
                    library.update(remote)
                }
            } else {
                library.add(remote)   // receiver: the book appears (audio materialized above)
            }
        }
        // SEND: refresh each synced book's state blob if the local copy is newer, and
        // capture its audio files as CKAssets.
        for record in repository.allAudiobookRecords() {
            guard let local = library.book(id: record.bookID) else { continue }
            let recorded = try? JSONDecoder().decode(Audiobook.self, from: record.blob)
            if (local.lastPlayedAt ?? .distantPast) > (recorded?.lastPlayedAt ?? .distantPast),
               let blob = try? JSONEncoder().encode(local) {
                record.blob = blob
                record.modifiedAt = Date()
            }
            captureAudio(book: local, library: library, repository: repository)
        }
        repository.save()
    }

    // MARK: - Audio CKAssets (mirrors AssetMaterializer, targeting the book folder)

    /// The files a synced book carries: its audio parts + `cover.jpg` when present.
    private static func syncedFilenames(_ book: Audiobook) -> [String] {
        book.files + (book.hasCover ? ["cover.jpg"] : [])
    }

    private static func captureAudio(book: Audiobook, library: AudiobookLibraryStore, repository: NotesRepository) {
        let folder = library.folder(for: book.id)
        let existing = Dictionary(repository.audiobookAssets(bookID: book.id).map { ($0.filename, $0) },
                                  uniquingKeysWith: { _, b in b })
        for name in syncedFilenames(book) {
            let url = folder.appendingPathComponent(name)
            guard let size = fileSize(url) else { continue }   // not on disk → nothing to upload
            if let asset = existing[name] {
                guard asset.byteCount != size, let data = try? Data(contentsOf: url) else { continue }
                asset.blob = data; asset.byteCount = data.count
            } else if let data = try? Data(contentsOf: url) {
                repository.context.insert(AudiobookAsset(bookID: book.id, filename: name, blob: data))
            }
        }
    }

    private static func materializeAudio(bookID: UUID, library: AudiobookLibraryStore, repository: NotesRepository) {
        let folder = library.folder(for: bookID)
        let assets = repository.audiobookAssets(bookID: bookID)
        guard !assets.isEmpty else { return }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for asset in assets where !asset.filename.isEmpty {
            let url = folder.appendingPathComponent(asset.filename)
            guard !FileManager.default.fileExists(atPath: url.path) else { continue }
            try? asset.blob.write(to: url, options: .atomic)
        }
    }

    private static func fileSize(_ url: URL) -> Int? {
        (try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? Int
    }
}
