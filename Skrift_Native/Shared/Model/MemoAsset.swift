import Foundation
import SwiftData

/// The binary payload of a `Memo` — its recording `.m4a` and any captured photos —
/// stored as a CloudKit-mirrored SwiftData row so the actual media (not just the
/// `Memo` text/metadata row) syncs across the user's own devices (standalone
/// Phase 1c). One `MemoAsset` per on-disk file.
///
/// **Why a separate `@Model` keyed by a loose `memoID` (not a `@Relationship`):**
/// CloudKit-backed SwiftData requires relationships to be optional + inverse-paired,
/// which is churn for no benefit here — the Mac already reconciles by filename/UUID,
/// and a loose foreign key matches that. Keeping the blob OUT of the `Memo` row also
/// means the hot queries (memos list / search) never fault a multi-MB blob into
/// memory; only asset operations touch `blob`.
///
/// **`blob` is plain `Data`, deliberately NOT `@Attribute(.externalStorage)`:**
/// `NSPersistentCloudKitContainer` (which SwiftData uses under CloudKit) does not
/// support external binary storage on a synced attribute — enabling it `fatalError`s
/// at container init. CloudKit instead promotes `Data` over ~1 MB to a `CKAsset`
/// automatically, which is exactly the audio/photo case, so the recording crosses
/// devices for free. The local cost is that the blob lives inline in the store; the
/// separate-row design keeps that off the `Memo` query path.
///
/// **CloudKit shape rules (mirrors `Memo`):** every attribute has a default (no
/// non-optional-without-default), and there is NO `@Attribute(.unique)` — uniqueness
/// is an app-level invariant (filenames embed the memo UUID, so they're globally
/// unique; `AssetMaterializer` dedups by filename before creating a row).
@Model
final class MemoAsset {
    /// The owning memo's UUID. Loose foreign key (see type doc) — not a relationship.
    var memoID: UUID = UUID()

    /// `Kind.audio` / `Kind.photo`. A free-form string (like `MemoMetadata.sourceType`)
    /// so a value written by a newer build never fails to decode on an older one.
    var kind: String = MemoAsset.Kind.audio

    /// The on-disk filename under `AppPaths.recordingsDirectory` (e.g.
    /// `memo_<uuid>.m4a`, `photo_<uuid>_001.jpg`). The materializer writes the blob
    /// back to exactly this name so all filename-based code stays unchanged.
    var filename: String = ""

    /// Byte length of `blob`. Lets the capture sweep detect a stale asset (e.g. after
    /// an append grows the audio) by comparing against the file size WITHOUT faulting
    /// the blob into memory.
    var byteCount: Int = 0

    /// The file's bytes. See type doc for why this is plain `Data` (no external storage).
    var blob: Data = Data()

    var createdAt: Date = Date()

    init(memoID: UUID, kind: String, filename: String, blob: Data, createdAt: Date = Date()) {
        self.memoID = memoID
        self.kind = kind
        self.filename = filename
        self.byteCount = blob.count
        self.blob = blob
        self.createdAt = createdAt
    }

    /// Known `kind` values. Stored as strings (see `kind`) — adding a kind needs no
    /// schema change. `wordTimings`/`diarization` are the per-memo JSON sidecars
    /// (Phase 1d) so karaoke/read-along + speaker labels survive the trip to another
    /// device.
    enum Kind {
        static let audio = "audio"
        static let photo = "photo"
        static let wordTimings = "wordTimings"
        static let diarization = "diarization"
    }
}
