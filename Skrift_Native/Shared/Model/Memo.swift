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
///
/// **Shared model (`Shared/Model/Memo.swift`):** this @Model is the SINGLE source of
/// the `Memo` CloudKit schema, compiled by BOTH the iOS app and the macOS app so the
/// Mac can be a CloudKit client of the phone's note store (`MAC_CLOUDKIT_PLAN.md`,
/// Fork A). It carries NO iOS couplings. The designated init is **blob-based**
/// (`metadataData` / `sharedContentData` as `Data?`) because SwiftData traps decoding a
/// nested-optional Codable @Model attribute (see below), NOT because the types are
/// unavailable — `MemoMetadata` is shared too (Shared/Model/MemoMetadata.swift) and the
/// typed `metadata` accessor lives here for both apps. `SharedContent` stays
/// mobile-typed (the desktop keeps a lenient legacy decoder of the same JSON under the
/// same name — CompilerBridge.swift), so its accessor, the on-disk path helpers
/// (`audioURL` / `sharedFileURL`), and the typed factory (`Memo.make(…)`) live in the
/// mobile-only `SkriftMobile/Models/Memo+Mobile.swift` extension.
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
    /// taken. Trusted by the Mac iff `Memo.isTrustedTranscript` (user-edited, or
    /// confidence ≥ `trustConfidenceThreshold`).
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

    /// Note reminder (feature wave chunk 7): WHEN to surface this memo. The
    /// reminder is DATA — it syncs like every field; each device derives its
    /// local notification from it (`ReminderScheduler`), so it rings whichever
    /// device you're holding and clears everywhere at once. A PAST date is
    /// inert history (never scheduled). ADDITIVE, nil default → lightweight
    /// migration; needs the prod CloudKit schema deploy at promotion.
    var remindAt: Date? = nil

    /// Locked note (feature wave chunk 8): opening requires device-owner auth
    /// (Face ID / Touch ID / passcode) on every device, and a locked memo is
    /// EXCLUDED from Obsidian publish (the vault is plaintext). The flag SYNCS
    /// — lock on one device, locked everywhere. v1 is an auth-gated UI, not
    /// per-note encryption (search and the pipeline keep working). ADDITIVE
    /// default → lightweight migration; prod CloudKit schema deploy needed.
    var locked: Bool = false

    /// Contextual capture payload + shared content, persisted as JSON blobs —
    /// NOT direct SwiftData Codable-struct attributes. SwiftData's internal decode
    /// of a nested-optional Codable struct traps at runtime (EXC_BREAKPOINT) the
    /// first time the attribute is read back; the blob + computed accessors (mobile
    /// extension) use our own JSON coder, which round-trips cleanly. Never queried by
    /// SwiftData; the shape feeds the Mac upload JSON. **Internal (not `private`)** so
    /// the mobile typed accessors AND the Mac's CloudKit ingest can read/write the raw
    /// bytes — the Mac forwards `metadataData` verbatim as the upload `audioMetadataJSON`.
    var metadataData: Data?
    var sharedContentData: Data?
    var annotationText: String?

    /// Per-note name-linking RESOLUTION choices, persisted as a JSON blob (same
    /// SwiftData-Codable-trap avoidance as `metadataData`). Holds the note's
    /// `unlinkedNames` (canonical keys kept plain — the "keep as plain text" / unlink
    /// gesture) + `namePicks` (alias → chosen canonical, or "" to silence) — exactly the
    /// `neverLink` / `namePicks` inputs the shared `Sanitiser` accepts. The phone keeps
    /// the transcript RAW and re-derives tiers (`Sanitiser.nameSpans`) against these on
    /// demand (`mocks/phone-name-linking.html`); they also steer the on-device Obsidian
    /// export. Phone-side display/export only — the mobile↔Mac contract (phone sends RAW,
    /// Mac links names with its OWN overrides) is untouched; the Mac's CloudKit ingest
    /// ignores this field. ADDITIVE, nil default → lightweight migration + CloudKit-safe.
    var nameResolutionsData: Data?

    /// The install that RECORDED this memo (`DeviceID.current`). With CloudKit a memo
    /// can arrive on another device still `.transcribing`; the receiver must NOT
    /// re-transcribe it (the recording device owns that, and the transcript will sync)
    /// — `recoverStuckTranscriptions` skips memos another device recorded. Additive,
    /// nil default → legacy/local memos (nil) stay recoverable. Syncs as a plain field.
    var recordingDeviceID: String? = nil

    /// Rescued from the Fading shelf ("Keep" — MemoLifecycle): a kept note never
    /// auto-fades again. ADDITIVE, nil default → lightweight SwiftData migration.
    var keptAt: Date? = nil

    /// In-flight marker for "Split speakers" (diarization). Non-nil = a diarization
    /// was started and hasn't completed: `0` = Auto, `N > 0` = forced to N speakers.
    /// Set before the diarize call, cleared (nil) when it completes — so a diarization
    /// orphaned by app suspension (the user backgrounds the app mid-identify, the
    /// fire-and-forget Task dies — 2026-06-21 device bug) is re-run by the launch
    /// sweep `recoverStuckDiarizations`, exactly like `.transcribing` recovery.
    /// ADDITIVE, nil default → lightweight SwiftData migration (safe for prod data).
    var pendingDiarizationTarget: Int? = nil

    /// Designated, **blob-based** initializer (desktop-compilable — no `MemoMetadata` /
    /// `SharedContent`). The mobile app constructs memos with typed contextual metadata
    /// via `Memo.make(metadata:sharedContent:…)` (the `Memo+Mobile.swift` extension),
    /// which encodes the blobs and forwards here.
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
        metadataData: Data? = nil,
        sharedContentData: Data? = nil,
        annotationText: String? = nil,
        nameResolutionsData: Data? = nil,
        recordingDeviceID: String? = DeviceID.current()
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
        self.metadataData = metadataData
        self.sharedContentData = sharedContentData
        self.annotationText = annotationText
        self.nameResolutionsData = nameResolutionsData
        self.recordingDeviceID = recordingDeviceID
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

    /// Parse a tag-entry string into individual tags: COMMA / newline separated (a
    /// tag may contain spaces, so we don't split on whitespace), each trimmed and
    /// de-`#`-ed, blanks dropped. Lets the user add several tags at once instead of
    /// one alert per tag (2026-06-21 "select a lot of tags" device feedback).
    static func parseTagInput(_ raw: String) -> [String] {
        raw.split(whereSeparator: { $0 == "," || $0 == "\n" })
            .map { $0.replacingOccurrences(of: "#", with: "").trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// Generic JSON helpers for the `metadataData` / `sharedContentData` blobs. Internal
    /// (not `private`) so the mobile typed accessors + `Memo.make` can use them.
    static func encodeJSON<T: Encodable>(_ value: T?) -> Data? {
        guard let value else { return nil }
        return try? JSONEncoder().encode(value)
    }

    static func decodeJSON<T: Decodable>(_ data: Data?) -> T? {
        guard let data else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    /// Typed contextual metadata, decoded from / encoded to the raw `metadataData` blob
    /// (the blob persists — SwiftData can't store the Codable struct directly, see
    /// `metadataData`). Shared: the phone writes it, the Mac's ingest reads it.
    var metadata: MemoMetadata? {
        get { Self.decodeJSON(metadataData) }
        set { metadataData = Self.encodeJSON(newValue) }
    }

    // MARK: - The mobile↔Mac transcript-trust rule

    /// The Mac re-transcribes a synced memo UNLESS the phone's transcript is trusted.
    /// ONE rule for both apps: hand-edited always wins; otherwise the on-device ASR
    /// confidence must clear this threshold (api/files.py heritage).
    static let trustConfidenceThreshold = 0.7

    /// `transcriptUserEdited || transcriptConfidence >= 0.7` — THE trust gate.
    static func isTrustedTranscript(userEdited: Bool, confidence: Double?) -> Bool {
        userEdited || (confidence ?? 0) >= trustConfidenceThreshold
    }
}
