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

    init(bookID: UUID, blob: Data, modifiedAt: Date = Date()) {
        self.bookID = bookID
        self.blob = blob
        self.modifiedAt = modifiedAt
    }
}

/// One audio file (or `cover.jpg`) of a synced audiobook, mirrored as a CloudKit
/// blob → CKAsset — the same pattern as `MemoAsset` (plain `Data`, no
/// `.externalStorage`; CloudKit auto-promotes `Data >~1 MB`). `AudiobookCloudSync`
/// materializes these back into the book's folder (`Documents/audiobooks/<bookID>/`)
/// on the receiving device. Only exists for books the user opted to sync — the big
/// files never leave the device for a local-only book.
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
