import Foundation
import SwiftData

/// Per-book sync carrier for an OPTED-IN audiobook (standalone Phase 1g/1h). Books
/// are local-only by default; flipping "Sync this book" creates one of these so the
/// book's state — and, via `AudiobookAsset`, its audio — syncs across the user's
/// devices and you resume anywhere.
///
/// `blob` is the JSON-encoded `Audiobook` value (reusing its existing `Codable`, the
/// same shape as `library.json`), so position / rate / lastPlayedAt / metadata ride
/// in one record. `AudiobookCloudSync` reconciles it with the local
/// `AudiobookLibraryStore` (LWW by `lastPlayedAt`); the library + player are untouched.
///
/// Existence of a record == the book is synced (the toggle's source of truth — no
/// separate flag). CloudKit shape rules: every attribute defaulted, no
/// `@Attribute(.unique)` (one record per `bookID` by convention).
@Model
final class AudiobookSyncRecord {
    var bookID: UUID = UUID()
    /// JSON-encoded `Audiobook` (the synced state).
    var blob: Data = Data()
    var modifiedAt: Date = Date()
    /// Set on the SOURCE device once its audio finished uploading to raw CloudKit.
    /// Doubles as the upload-once guard AND the receiver's pull trigger: this is a
    /// real change to a synced @Model, so it exports + pushes (Core Data's zone DOES
    /// push), and the peer's import nudges `reconcile` to fetch the audio by id — no
    /// separate CKQuerySubscription needed (the default zone wouldn't push one anyway).
    var audioUploadedAt: Date? = nil

    init(bookID: UUID, blob: Data, modifiedAt: Date = Date(), audioUploadedAt: Date? = nil) {
        self.bookID = bookID
        self.blob = blob
        self.modifiedAt = modifiedAt
        self.audioUploadedAt = audioUploadedAt
    }
}

/// LEGACY — superseded by the raw-CloudKit `AudiobookAudioTransport`. Audiobook audio
/// no longer rides a SwiftData `Data` blob (which gave only an INDETERMINATE bar,
/// since `NSPersistentCloudKitContainer` exposes no upload %); it now transfers as raw
/// `CKRecord` + `CKAsset(fileURL:)` for a REAL per-book transfer percentage. This
/// `@Model` is intentionally RETAINED (no longer written) — dropping a synced @Model
/// risks a load `fatalError` against the already-deployed dev CloudKit schema, and
/// keeping it is additive-safe. Remove it at prod promotion with a CloudKit dev-env
/// reset. `deleteAudiobookSync` still purges any stale rows from build (11).
@Model
final class AudiobookAsset {
    var bookID: UUID = UUID()
    var filename: String = ""
    var byteCount: Int = 0
    var blob: Data = Data()
    var createdAt: Date = Date()

    init(bookID: UUID, filename: String, blob: Data, createdAt: Date = Date()) {
        self.bookID = bookID
        self.filename = filename
        self.byteCount = blob.count
        self.blob = blob
        self.createdAt = createdAt
    }
}
