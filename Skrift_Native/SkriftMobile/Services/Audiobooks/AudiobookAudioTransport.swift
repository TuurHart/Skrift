import Foundation

/// One audio file (or `cover.jpg`) of a synced audiobook, addressed by a stable
/// CloudKit `recordName` and carrying its on-disk source URL (upload) + display
/// filename (materialize). The `recordName` is index-based (`ab_<bookID>_<n>` /
/// `ab_<bookID>_cover`) — NOT the raw filename — so it stays ASCII, slash-free and
/// reserved-prefix-safe (the queryable-index audit flagged that filenames can be
/// non-ASCII / contain `/`, and CloudKit only blesses "ASCII, ≤255, no leading `_`").
struct AudiobookAudioPart: Sendable {
    let recordName: String
    let filename: String
    let fileURL: URL
}

/// A reference to a synced audio record the receiver wants to pull: its stable
/// `recordName` + the local `filename` to write it back as. Both devices compute
/// these identically from the synced `Audiobook` (`files` order + `hasCover`), so the
/// receiver can fetch by exact `CKRecord.ID` — no CloudKit query / queryable index.
struct AudiobookAudioRef: Sendable {
    let recordName: String
    let filename: String
}

/// Moves an opted-in audiobook's large audio files across the user's devices with a
/// REAL per-book transfer percentage. SwiftData / `NSPersistentCloudKitContainer`
/// auto-mirroring exposes no upload %, so the audio rides a RAW CloudKit transfer
/// instead (`CKModifyRecordsOperation`/`CKFetchRecordsOperation` +
/// `perRecordProgressBlock`); the book's *state* (position/rate/bookmarks) keeps
/// riding the SwiftData carrier (`AudiobookSyncRecord`). The `progress` closure
/// reports a 0–1 BOOK-level fraction (byte-weighted across the book's files) and may
/// be called off the main thread — callers hop to `@MainActor` before touching UI.
protocol AudiobookAudioTransport: Sendable {
    /// Upload the given local files as records (each carrying a `CKAsset(fileURL:)`,
    /// so the bytes stream off-disk — never loaded into memory). Idempotent: a
    /// re-upload overwrites by `recordName`.
    func upload(_ parts: [AudiobookAudioPart], progress: @Sendable @escaping (Double) -> Void) async throws

    /// Download the referenced records by exact id into `destFolder`, written under
    /// each ref's `filename`. The fetched asset stages to a temp file → copied into
    /// place immediately (CloudKit reclaims the staging area).
    func download(_ refs: [AudiobookAudioRef], into destFolder: URL, progress: @Sendable @escaping (Double) -> Void) async throws

    /// Drop the records (unshare / stop syncing) — frees the iCloud copy. Local files
    /// on every device are left untouched (the caller owns that policy).
    func delete(recordNames: [String]) async throws
}

/// Offline stand-in for `CloudKitAudiobookTransport`: the "audio cloud" is a plain
/// in-memory `[recordName: Data]` dictionary. Tests share ONE instance between two
/// `AudiobookLibraryStore`s (device A / device B), exactly mirroring how the real
/// transport's private CloudKit DB is shared across a user's devices — so the sync
/// tests stay deterministic + offline (no CloudKit, like `cloudKitDatabase: .none`).
final class InMemoryAudiobookTransport: AudiobookAudioTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var store: [String: Data] = [:]

    func upload(_ parts: [AudiobookAudioPart], progress: @Sendable @escaping (Double) -> Void) async throws {
        for part in parts {
            let data = (try? Data(contentsOf: part.fileURL)) ?? Data()
            lock.lock(); store[part.recordName] = data; lock.unlock()
        }
        progress(1)
    }

    func download(_ refs: [AudiobookAudioRef], into destFolder: URL, progress: @Sendable @escaping (Double) -> Void) async throws {
        try FileManager.default.createDirectory(at: destFolder, withIntermediateDirectories: true)
        for ref in refs {
            lock.lock(); let data = store[ref.recordName]; lock.unlock()
            guard let data else { continue }
            let dest = destFolder.appendingPathComponent(ref.filename)
            try? FileManager.default.removeItem(at: dest)
            try data.write(to: dest, options: .atomic)
        }
        progress(1)
    }

    func delete(recordNames: [String]) async throws {
        lock.lock(); for name in recordNames { store[name] = nil }; lock.unlock()
    }

    // MARK: - Test introspection
    func has(_ recordName: String) -> Bool { lock.lock(); defer { lock.unlock() }; return store[recordName] != nil }
    func data(_ recordName: String) -> Data? { lock.lock(); defer { lock.unlock() }; return store[recordName] }
    var count: Int { lock.lock(); defer { lock.unlock() }; return store.count }
}
