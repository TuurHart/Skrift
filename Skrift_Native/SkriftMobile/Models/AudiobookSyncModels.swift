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
    /// Content signature of the read-along transcript sidecars the SOURCE has uploaded
    /// (`"<fileIndex>:<coveredUpTo>:<wordCount>"` joined). The receiver pulls the
    /// sidecars whenever this changes (so a book transcribed AFTER it was synced still
    /// propagates), then re-stamps them to its own audio. Empty = no transcript yet.
    var transcriptSignature: String = ""
    /// 📖 spike 6: content signature of the alignment sidecars the SOURCE has uploaded
    /// (`"<fileIndex>:<verdict>:<sentenceCount>:<textCount>"` joined —
    /// `FileAlignment.cloudSignaturePart()`; 4th field added with schema-3 multi-text).
    /// The receiver pulls them whenever this changes, same idea as `transcriptSignature`, but
    /// only APPLIES them (derives `epubChapters`) once every landed sidecar is fresh against
    /// this device's own transcript — alignment sidecars are never restamped. Empty = none yet.
    var alignmentSignature: String = ""

    init(bookID: UUID, blob: Data, modifiedAt: Date = Date(), audioUploadedAt: Date? = nil,
         transcriptSignature: String = "", alignmentSignature: String = "") {
        self.bookID = bookID
        self.blob = blob
        self.modifiedAt = modifiedAt
        self.audioUploadedAt = audioUploadedAt
        self.transcriptSignature = transcriptSignature
        self.alignmentSignature = alignmentSignature
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

/// Per-book BOOKMARK list carrier (iPad wave, 2026-07-23 — Tuur: "make sure that
/// bookmarks and everything are synced"). Whole-list LWW by `modifiedAt` (the
/// custom-vocab pattern: a delete on one device propagates; a union would
/// resurrect it). Deliberately its OWN record type — never a field on
/// `AudiobookSyncRecord` — so a pre-wave writer re-encoding that record can't
/// erase it (the 2026-07-22 additive-field lesson). One record per `bookID` by
/// convention (dupes collapse in the sync core). CloudKit shape rules: every
/// attribute defaulted, no `@Attribute(.unique)`.
@Model
final class AudiobookBookmarksRecord {
    var bookID: UUID = UUID()
    /// JSON-encoded `[AudiobookBookmark]`, position-sorted.
    var itemsBlob: Data = Data()
    var modifiedAt: Date = Date()

    init(bookID: UUID, itemsBlob: Data, modifiedAt: Date = Date()) {
        self.bookID = bookID
        self.itemsBlob = itemsBlob
        self.modifiedAt = modifiedAt
    }
}
