import Foundation
import SwiftData

/// Local sync state. Mirrors the RN `Memo.syncStatus` ('waiting' | 'synced').
enum SyncStatus: String, Codable, Sendable {
    case waiting
    case synced
}

/// On-device transcription state. Mirrors the RN `TranscriptStatus`.
enum TranscriptStatus: String, Codable, Sendable {
    case pending
    case transcribing
    case done
    case failed
}

/// Trash retention, mirroring Apple Voice Memos' "Recently Deleted" (~2 weeks).
/// A soft-deleted memo (`deletedAt != nil`) keeps its audio/sidecars on disk so
/// Restore is lossless; the startup purge permanently removes it once expired.
enum TrashPolicy {
    /// Days a trashed memo survives before the startup purge removes it for good.
    static let retentionDays = 14
    static var retention: TimeInterval { TimeInterval(retentionDays) * 86_400 }
}

/// A captured voice memo. Mirrors the RN `Memo` shape (`Mobile/lib/storage.ts`)
/// plus the mobile↔Mac contract fields the backend trusts.
@Model
final class Memo {
    /// Stable identity. Audio filenames embed it (`memo_{uuid}.m4a`) and the Mac
    /// reconciles uploads by filename — so this UUID is the contract spine. Never
    /// regenerate it for an existing memo.
    ///
    /// NOT `@Attribute(.unique)`: CloudKit-backed SwiftData (standalone Phase 1 internal
    /// sync) forbids unique constraints. Uniqueness is an app-level invariant instead —
    /// we never regenerate an id, and the only re-insert path (the capture-inbox drainer)
    /// already dedups via `NotesRepository.memo(id:)` before inserting (so dropping the
    /// constraint changes no behavior). All other inserts mint a fresh UUID.
    var id: UUID = UUID()

    /// Audio is stored by filename and resolved against the recordings dir at
    /// runtime — an absolute URL would break across reinstalls (the app-container
    /// UUID changes), and the filename already carries the memo UUID. Empty for
    /// capture items with no audio annotation.
    var audioFilename: String = ""

    var duration: TimeInterval = 0
    var recordedAt: Date = Date()
    var tags: [String] = []
    var syncStatus: SyncStatus = SyncStatus.waiting

    /// Optional phone-set title (Memo detail). Sent in the upload metadata; the
    /// Mac may use it in its title chooser instead of the LLM title. When unset,
    /// the UI falls back to the transcript's first line.
    var title: String?

    /// On-device transcript. Contains `[[img_NNN]]` markers when photos were
    /// taken. Trusted by the Mac iff `transcriptUserEdited || confidence >= 0.7`.
    var transcript: String?
    var transcriptStatus: TranscriptStatus = TranscriptStatus.pending
    var transcriptConfidence: Double?
    var transcriptUserEdited: Bool = false
    /// True when `[[img_NNN]]` markers are already injected — tells the Mac not
    /// to re-inject them.
    var transcriptMarkersInjected: Bool = false

    /// Manual importance rating (0–1, snapped to 0.1), mirroring the desktop review
    /// slider. **Gates sync (flag-to-send): 0 = the memo STAYS on the phone; > 0 =
    /// eligible to upload to the Mac.** Sent in the upload metadata when > 0 so the
    /// Mac pre-fills its own significance slider. Default 0 (unrated → not synced).
    var significance: Double = 0

    /// Soft-delete marker (Recently Deleted). Non-nil = in the trash: hidden from
    /// the main list/search and never uploaded; purged permanently (audio +
    /// sidecars included) once it's `TrashPolicy.retention` old. ADDITIVE with a
    /// nil default → lightweight SwiftData migration (safe for prod data).
    var deletedAt: Date? = nil

    /// When the memo entered Skrift (recorded / imported / shared). DISTINCT from
    /// `recordedAt` (when the CONTENT happened — e.g. a shared video keeps its
    /// filming date in `recordedAt`). ADDITIVE, nil default → lightweight migration;
    /// legacy memos (nil) fall back to `recordedAt` via `addedAt`.
    var createdAt: Date? = nil

    /// Last content edit (title / transcript / tags / append / trim). nil until
    /// first edited → falls back to `createdAt`/`recordedAt` via `lastEditedAt`.
    /// ADDITIVE, nil default → lightweight migration.
    var editedAt: Date? = nil

    /// Contextual capture payload + shared content, persisted as JSON blobs —
    /// NOT direct SwiftData Codable-struct attributes. SwiftData's internal decode
    /// of a nested-optional Codable struct traps at runtime (EXC_BREAKPOINT) the
    /// first time the attribute is read back; the blob + computed accessors below
    /// use our own JSON coder, which round-trips cleanly. Never queried by
    /// SwiftData; the shape feeds the Mac upload JSON.
    private var metadataData: Data?
    private var sharedContentData: Data?
    var annotationText: String?

    init(
        id: UUID = UUID(),
        audioFilename: String = "",
        duration: TimeInterval = 0,
        recordedAt: Date = Date(),
        tags: [String] = [],
        syncStatus: SyncStatus = .waiting,
        title: String? = nil,
        transcript: String? = nil,
        transcriptStatus: TranscriptStatus = .pending,
        transcriptConfidence: Double? = nil,
        transcriptUserEdited: Bool = false,
        transcriptMarkersInjected: Bool = false,
        significance: Double = 0,
        deletedAt: Date? = nil,
        createdAt: Date? = Date(),
        editedAt: Date? = nil,
        metadata: MemoMetadata? = nil,
        sharedContent: SharedContent? = nil,
        annotationText: String? = nil
    ) {
        self.id = id
        self.audioFilename = audioFilename
        self.duration = duration
        self.recordedAt = recordedAt
        self.tags = tags
        self.syncStatus = syncStatus
        self.title = title
        self.transcript = transcript
        self.transcriptStatus = transcriptStatus
        self.transcriptConfidence = transcriptConfidence
        self.transcriptUserEdited = transcriptUserEdited
        self.transcriptMarkersInjected = transcriptMarkersInjected
        self.significance = significance
        self.deletedAt = deletedAt
        self.createdAt = createdAt
        self.editedAt = editedAt
        self.metadataData = Self.encodeJSON(metadata)
        self.sharedContentData = Self.encodeJSON(sharedContent)
        self.annotationText = annotationText
    }

    /// Resolved on-disk audio location, or nil for memos without audio.
    var audioURL: URL? {
        audioFilename.isEmpty ? nil : AppPaths.recordingsDirectory.appendingPathComponent(audioFilename)
    }

    /// When the memo entered Skrift — legacy memos (nil `createdAt`) fall back to
    /// `recordedAt`. The "Recently added" sort key.
    var addedAt: Date { createdAt ?? recordedAt }

    /// Last content edit — never-edited memos fall back to added/recorded. The
    /// "Recently edited" sort key.
    var lastEditedAt: Date { editedAt ?? createdAt ?? recordedAt }

    /// Bump the edited timestamp. Call from content-edit sites (title, transcript,
    /// tags, append, trim) — NOT from sync-status / significance changes.
    func markEdited(_ date: Date = Date()) { editedAt = date }

    var metadata: MemoMetadata? {
        get { Self.decodeJSON(metadataData) }
        set { metadataData = Self.encodeJSON(newValue) }
    }

    var sharedContent: SharedContent? {
        get { Self.decodeJSON(sharedContentData) }
        set { sharedContentData = Self.encodeJSON(newValue) }
    }

    private static func encodeJSON<T: Encodable>(_ value: T?) -> Data? {
        guard let value else { return nil }
        return try? JSONEncoder().encode(value)
    }

    private static func decodeJSON<T: Decodable>(_ data: Data?) -> T? {
        guard let data else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }
}
