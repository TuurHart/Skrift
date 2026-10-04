import Foundation
import SwiftData

/// Per-step pipeline state. Mirrors the Electron app's `ProcessingSteps`
/// (`frontend-new/src/types/pipeline.ts`) and the backend `status.json` `steps`.
enum StepStatus: String, Codable, Sendable {
    case pending, processing, done, error, skipped
}

/// Value type for the four step states. NOT stored directly on the @Model (see the
/// SwiftData gotcha below) — exposed via a computed accessor over enum columns.
struct ProcessingSteps: Codable, Equatable, Sendable {
    var transcribe: StepStatus = .pending
    var sanitise: StepStatus = .pending
    var enhance: StepStatus = .pending
    var export: StepStatus = .pending
}

enum SourceType: String, Codable, Sendable {
    case audio, note, capture
}

// `NameCandidate` + `AmbiguousOccurrence` (the Sanitiser's suggested-tier result type)
// moved to the shared cross-app source `Skrift_Native/Shared/Naming/NameMatch.swift` in
// standalone Phase 0, so the phone compiles the same name-linking engine (it has no
// `PipelineFile`). Both apps reference them via their `project.yml` Shared/Naming source.

/// The ingest-queue item — the desktop's processing entity (the Mac equivalent of
/// the phone's `Memo`, but richer because it carries full pipeline state). Ported
/// from `frontend-new/src/types/pipeline.ts` `PipelineFile`.
///
/// SwiftData gotcha (learned on the iOS track): SwiftData TRAPS when decoding a
/// raw Codable-struct attribute on read-back. So Codable structs/arrays are stored
/// as enum columns (String-RawValue enums are safe) or JSON `Data?` blobs, with
/// computed accessors. Primitive arrays like `[String]` are fine.
@Model
final class PipelineFile {
    /// Stable id. For phone-synced memos this is the memo UUID (the upload
    /// reconciles by filename, which embeds it) — the contract spine.
    @Attribute(.unique) var id: String = UUID().uuidString

    var filename: String = ""
    /// Absolute path to the working folder's original media (e.g. `…/original.m4a`).
    var path: String = ""
    var size: Int = 0
    var sourceType: SourceType = SourceType.audio
    /// Finer-grained source marker WITHIN an audio memo (which is processed as
    /// audio either way) — the unified source taxonomy: `"video"` for a video
    /// import (phone-uploaded or desktop-ingested). Drives the source glyph +
    /// label. ADDITIVE, nil default → lightweight SwiftData migration.
    var mediaSource: String? = nil

    // Step state as individual enum columns (safe; ProcessingSteps struct is NOT
    // a stored attribute — see the gotcha note above).
    var transcribeStatus: StepStatus = StepStatus.pending
    var sanitiseStatus: StepStatus = StepStatus.pending
    var enhanceStatus: StepStatus = StepStatus.pending
    var exportStatus: StepStatus = StepStatus.pending

    var uploadedAt: Date = Date()
    var lastActivityAt: Date?

    /// Live bidirectional sync: the source `Memo`'s `lastEditedAt` (or a phone-authored
    /// `MemoEnhancement.enhancedAt`) that this row last reflected. Set at ingest, then bumped
    /// by `MemoCloudUpdate` when a NEWER phone edit arrives over CloudKit — the watermark that
    /// tells "the phone changed this after I ingested it" apart from "already up to date", so
    /// re-link+recompile runs once per edit and never loops. Additive/optional → lightweight
    /// migration; nil on rows ingested before this shipped (treated as "reflect the next edit").
    var syncedSourceEditedAt: Date?

    /// Trash-state sync watermark: the `Memo.deletedAt` this row last reflected. Lets the
    /// reconciler mirror a phone trash/restore onto `deletedAt` WITHOUT clobbering a Mac-local
    /// trash that predates delete-sync (it reflects only when `memo.deletedAt` differs from this
    /// watermark — a real change on the phone — not merely from the row's current state). nil on
    /// rows from before this shipped (treated as "reflect the next trash change").
    var syncedSourceDeletedAt: Date?

    /// Mirror of the synced `Memo.locked` (phone feature wave chunk 8): a locked note is
    /// EXCLUDED from vault export (the vault is plaintext — `VaultExporter` refuses) and its
    /// body/copy actions are gated behind device-owner auth (`LockGate`). Processing keeps
    /// working (v1 = auth-gated UI, not encryption — same as the phone). Set at ingest,
    /// kept fresh by `MemoCloudUpdate`. ADDITIVE default → lightweight migration.
    var locked: Bool = false

    /// Mirror of the synced `Memo.remindAt` — shown in the properties card. The ALARM is
    /// per-device by design (the phone/iPad schedule notifications); the Mac just surfaces
    /// the date. ADDITIVE, nil default → lightweight migration.
    var remindAt: Date? = nil

    /// Flat OCR text of the memo's photos (phone-authored Vision text riding the synced
    /// metadata blob's `imageManifest[].text`) — mirrored here so search matches what's
    /// IN a photo without decoding JSON per keystroke. ADDITIVE, nil default.
    var imageOCRText: String? = nil

    // Transcription / sanitisation
    var transcript: String?
    var sanitised: String?
    /// `[AmbiguousOccurrence]` stored as a JSON blob (struct arrays trap SwiftData).
    var ambiguousNamesJSON: Data?
    /// The note's name DECISIONS (unlink / pick / silence) — the SAME blob as the synced
    /// `Memo.nameResolutionsData` (`NameResolutions`, Shared/Naming), so the Mac mirrors it
    /// both ways (C81, D20, R37). Read/write through `nameResolutions` (or the
    /// `unlinkedNames` / `namePicks` views). nil = no decisions.
    var nameResolutionsData: Data?
    /// LEGACY Mac-only copies (pre-2026-10), kept ONLY as a migration source: read once
    /// through `nameResolutions` and cleared on the first write. Renamed with
    /// `originalName` so existing rows keep their data across the lightweight migration.
    /// Delete both once every installed Mac has written its rows through (C81).
    @Attribute(originalName: "unlinkedNames") var legacyUnlinkedNames: [String] = []
    @Attribute(originalName: "namePicksJSON") var legacyNamePicksJSON: Data?
    /// `[WordTiming]` stored as a JSON blob (the per-file `word_timings.json`
    /// equivalent) — drives the karaoke highlight. Set by the transcribe step.
    var wordTimingsJSON: Data?
    /// `[DiarizedSegment]` stored as a JSON blob. Persisted by the conversation-mode diarize step so a
    /// speaker's audio can be re-extracted later — to ENROLL their voice from the Mac
    /// review screen — WITHOUT re-diarizing. Empty for monologues / phone-attributed
    /// memos the Mac never split.
    var diarizationSegmentsJSON: Data?

    // Enhancement (review-time fields)
    var enhancedTitle: String?
    var titleSuggested: String?
    var enhancedCopyedit: String?
    var enhancedSummary: String?
    var tags: [String] = []
    /// Deterministic tag candidates. Refined to the richer Record<word,[tags]>
    /// shape in Phase 5.
    var tagSuggestions: [String]?
    /// Manual review-time slider value (plain YAML number on export).
    var significance: Double?

    /// WHERE this note goes when it leaves Skrift (`NoteDestination`). The Mac edits a
    /// `PipelineFile`, so it carries its own copy and mirrors it onto the synced `Memo`
    /// exactly the way the rating does — see `MacCloudMetaSync.setDestination`.
    /// Non-optional with a `.personal` default: unlike `significance`, there is no
    /// "never set" state to be ambiguous about.
    var destinationRaw: String = NoteDestination.personal.rawValue

    /// Typed access to `destinationRaw`. Unknown values read as `.personal` — an
    /// unreadable destination must never be guessed as one that LEAVES.
    var destination: NoteDestination {
        get { NoteDestination(rawValue: destinationRaw) ?? .personal }
        set { destinationRaw = newValue.rawValue }
    }

    // Export
    var exported: String?
    var compiledText: String?
    var includeAudioInExport: Bool = true

    // Misc
    var error: String?
    /// Phone-sent metadata (location/weather/pressure/imageManifest/…), preserved
    /// VERBATIM as raw JSON so a desktop edit never clobbers it. Typed accessors
    /// land with the upload handler in Phase 2.
    var audioMetadataJSON: Data?

    /// A person edited this transcript mid-take (the m2 live-recording surface) — mirrors
    /// `Memo.transcriptUserEdited` so the note pane can say so (`NoteProperties`' "✎ edited
    /// while recording" chip) without resolving the synced Memo on every render. Set at
    /// finalize by `LiveRecordingSession.stop()`'s edited branch; additive + defaulted →
    /// existing stores migrate lightweight.
    var transcriptUserEdited: Bool = false

    /// This file was RECORDED here, not imported. The rating is consent, and capturing a
    /// thought isn't judging it, so a capture stays unrated. (An import arrives unrated too
    /// since D159 — see `isLocalImport`; the two flags differ in what else they drive: names,
    /// location, the edited-take signal.)
    ///
    /// It has to be a stored fact rather than a call-site argument, because the two things
    /// that act on it run on different clocks: the arrival path authors the Memo immediately,
    /// and `MemoCloudReconciler`'s sweep authors one for any local row that still lacks it.
    /// Whichever gets there first wins (`MacMemoAuthor.author` is idempotent) — and on
    /// 2026-07-28 the sweep won, floored a real Mac take to 0.1, and put a note nobody had
    /// judged into the queue on both devices. Written on the row, both callers agree no
    /// matter who arrives first. Additive + defaulted → existing stores migrate lightweight.
    var isLocalRecording: Bool = false

    /// This file was IMPORTED on this Mac (the Import panel / drag-drop / Photos promise), as
    /// opposed to recorded or synced from the phone. Stamped at construction by
    /// `IngestService`, for the same race reason as `isLocalRecording`. D159 (2026-09-30): an
    /// import arrives UNRATED like a recording — it is transcribed, but enters the Process
    /// queue only once rated. Rows imported before this flag existed read `false` and keep
    /// their old nil-means-rated reading (their Memo was authored at the 0.1 floor).
    /// Additive + defaulted → existing stores migrate lightweight.
    var isLocalImport: Bool = false

    /// A row born on THIS Mac (recorded or imported) rather than synced from the phone.
    var isLocalCapture: Bool { isLocalRecording || isLocalImport }

    /// C102: diarization is opt-in PER NOTE. Only a note the user asked to split ("Split
    /// speakers") carries this; a Mac import never diarizes without it, whatever
    /// `settings.json` says. Additive + defaulted → existing stores migrate lightweight.
    var diarizeRequested: Bool = false

    /// Soft-delete — "Recently Deleted", mirroring the phone + Apple Voice Memos.
    /// A trashed file (`deletedAt != nil`) is hidden from the sidebar/queue,
    /// excluded from the phone's `GET /api/files/` list, and never processed; its
    /// on-disk working folder STAYS so Restore is lossless. The launch purge
    /// removes the record (+ trashes the folder) once `TrashPolicy.retention`
    /// old. Additive + optional → existing stores migrate lightweight.
    var deletedAt: Date?

    /// Whole days left before the launch purge removes a trashed file for good.
    func trashDaysRemaining(now: Date = Date()) -> Int {
        guard let deletedAt else { return TrashPolicy.retentionDays }
        let elapsed = now.timeIntervalSince(deletedAt)
        return max(0, TrashPolicy.retentionDays - Int(elapsed / 86_400))
    }

    init(
        id: String = UUID().uuidString,
        filename: String = "",
        path: String = "",
        size: Int = 0,
        sourceType: SourceType = .audio,
        uploadedAt: Date = Date()
    ) {
        self.id = id
        self.filename = filename
        self.path = path
        self.size = size
        self.sourceType = sourceType
        self.uploadedAt = uploadedAt
    }

    /// Read-only view over the four step columns (write the columns directly).
    var steps: ProcessingSteps {
        ProcessingSteps(transcribe: transcribeStatus, sanitise: sanitiseStatus,
                        enhance: enhanceStatus, export: exportStatus)
    }

    /// Decoded ambiguous-name occurrences (backed by `ambiguousNamesJSON`). In the OPT-OUT
    /// model these are the *suggested* tier — recognised-but-not-auto-linked occurrences
    /// (ambiguous twins + common-word names) the review surface renders dotted (chunk 4).
    var ambiguousNames: [AmbiguousOccurrence]? {
        get { ambiguousNamesJSON.flatMap { try? JSONDecoder().decode([AmbiguousOccurrence].self, from: $0) } }
        set { ambiguousNamesJSON = newValue.flatMap { try? JSONEncoder().encode($0) } }
    }

    /// True while this row still carries pre-shared-blob decisions nobody has migrated.
    var hasLegacyNameResolutions: Bool {
        nameResolutionsData == nil && (!legacyUnlinkedNames.isEmpty || legacyNamePicksJSON != nil)
    }

    /// The note's name decisions (shared shape). Reads fold in un-migrated legacy data;
    /// every write lands in the shared blob and clears the legacy copies.
    var nameResolutions: NameResolutions {
        get {
            if nameResolutionsData != nil { return NameResolutions.decode(nameResolutionsData) }
            let picks = legacyNamePicksJSON.flatMap { try? JSONDecoder().decode([String: String].self, from: $0) } ?? [:]
            return NameResolutions(unlinkedNames: legacyUnlinkedNames, namePicks: picks)
        }
        set {
            nameResolutionsData = newValue.encoded
            if !legacyUnlinkedNames.isEmpty { legacyUnlinkedNames = [] }
            if legacyNamePicksJSON != nil { legacyNamePicksJSON = nil }
        }
    }

    /// Canonical keys pruned for this whole note — the `Sanitiser.neverLink` input.
    var unlinkedNames: [String] {
        get { nameResolutions.unlinkedNames }
        set { var r = nameResolutions; r.unlinkedNames = newValue; nameResolutions = r }
    }

    /// Per-note "which person?" picks — alias (lowercased) → chosen canonical `[[Name]]`,
    /// or "" to silence. The `Sanitiser.namePicks` input.
    var namePicks: [String: String] {
        get { nameResolutions.namePicks }
        set { var r = nameResolutions; r.namePicks = newValue; nameResolutions = r }
    }

    /// Per-word transcript timings (backed by `wordTimingsJSON`) — drives karaoke.
    var wordTimings: [WordTiming] {
        get { wordTimingsJSON.flatMap { try? JSONDecoder().decode([WordTiming].self, from: $0) } ?? [] }
        set { wordTimingsJSON = newValue.isEmpty ? nil : (try? JSONEncoder().encode(newValue)) }
    }

    /// Per-speaker diarization time-ranges (backed by `diarizationSegmentsJSON`).
    /// Retained from the conversation-mode diarize step so the review screen can later
    /// extract one speaker's audio and enroll their voice
    /// (`DiarizationService.embedSpeaker(audioURL:segments:slot:)`).
    var diarizationSegments: [DiarizedSegment] {
        get { diarizationSegmentsJSON.flatMap { try? JSONDecoder().decode([DiarizedSegment].self, from: $0) } ?? [] }
        set { diarizationSegmentsJSON = newValue.isEmpty ? nil : (try? JSONEncoder().encode(newValue)) }
    }

    /// The C2 book fields when this file is an audiobook quote capture, else nil —
    /// no `bookTitle` in the metadata blob (every plain memo, and every upload from
    /// an older phone build). Decoded through the Compiler's lenient `PhoneMetadata`
    /// shape with the same trimming, so the presentation layer (sidebar glyph,
    /// properties source row, quote attribution) can never disagree with the export
    /// about whether a memo is a book capture.
    var bookCapture: BookCapture? {
        guard let data = audioMetadataJSON,
              let meta = MemoMetadata.lenient(from: data),
              let title = BookCapture.trimmedNonEmpty(meta.bookTitle) else { return nil }
        return BookCapture(title: title,
                           author: BookCapture.trimmedNonEmpty(meta.bookAuthor),
                           chapter: BookCapture.trimmedNonEmpty(meta.bookChapter))
    }

    /// D175 / C172: the leading `> ` block is read-only in the editor only when this note is a
    /// real captured quote (an audiobook / text capture carries the book fields). A blockquote
    /// the user typed by hand on any other note stays editable.
    var hasLockedQuote: Bool { bookCapture != nil }

    /// The shared thing a capture memo carries (url / text / file), decoded from the
    /// metadata blob; nil for everything else.
    var sharedContent: SharedContent? { SharedContent.decode(from: audioMetadataJSON) }

    /// Ambient CONTEXT chips — place · weather · daypart — the phone shows under the
    /// title (`MemoDetailView.metaChips`). Decoded from the synced metadata blob through
    /// the lenient `PhoneMetadata` (typed `location`/`weather`/`dayPeriod` keys, the shape
    /// the phone actually syncs — the old Mac properties row read demo-only `phone_location`
    /// keys, so real memos showed nothing). Empty for captures / older uploads with no context.
    var contextChips: [(text: String, symbol: String)] { contextChips(includeDayPeriod: true) }

    /// `contextChips`, optionally without the daypart chip (the Mac header shows date · place ·
    /// weather only).
    func contextChips(includeDayPeriod: Bool) -> [(text: String, symbol: String)] {
        guard sourceType != .capture, let data = audioMetadataJSON,
              let meta = MemoMetadata.lenient(from: data) else { return [] }
        var chips: [(String, String)] = []
        if let place = meta.location?.placeName?.trimmingCharacters(in: .whitespaces), !place.isEmpty {
            chips.append((place, "mappin.circle.fill"))
        }
        if let t = meta.weather?.temperature {
            chips.append(("\(Int(t.rounded()))°", "cloud.sun.fill"))
        }
        if includeDayPeriod, let raw = meta.dayPeriod, let period = DayPeriod(rawValue: raw) {
            chips.append((period.label, period.symbol))   // shared label/symbol → phone parity
        }
        return chips
    }
}

/// Audiobook quote-capture (contract C2): the book fields a capture memo rides on
/// the phone metadata JSON. The mirror of the phone's `Memo.isBookCapture` /
/// `bookCaptionLabel` display helpers.
struct BookCapture: Equatable, Sendable {
    var title: String
    var author: String?
    var chapter: String?

    /// Plain-text attribution caption — "— Author, Book · ch. N", with the author /
    /// chapter pieces omitted when absent. A purely numeric chapter gets the "ch. "
    /// prefix; anything else (an m4b chapter *name*) shows as-is, matching the
    /// phone's rows. PLAIN text by design: the real `[[Author]]` wikilink is written
    /// at export only (`Compiler.audiobookBody`) — never duplicated into the body.
    var attribution: String {
        CaptureQuote.attribution(book: title, author: author, chapter: chapter) ?? title
    }

    /// Char ranges of the leading blockquote lines — now just the SHARED rule
    /// (`CaptureQuote.lineRanges`), so the Mac's editor styling can't drift from the phone's.
    /// Presentation only: the stored text keeps its raw `> ` lines.
    static func quoteLineRanges(in text: String) -> [NSRange] {
        CaptureQuote.lineRanges(in: text)
    }

    static func trimmedNonEmpty(_ v: String?) -> String? {
        guard let t = v?.trimmingCharacters(in: .whitespaces), !t.isEmpty else { return nil }
        return t
    }
}

extension PipelineFile {
    /// Audio duration in seconds from the phone metadata blob (0 when absent).
    ///
    /// Reads BOTH shapes that blob has carried, because both are in live stores:
    /// `MemoCloudIngest.metadataJSON` writes `duration` as a **number of seconds**
    /// (`memo.duration`, a `TimeInterval`), while the HTTP-era uploads and the
    /// demo/snapshot seeds write an **`"HH:MM:SS"` string**.
    ///
    /// This used to parse the string ONLY (`as? String`), so every CloudKit-synced note
    /// reported 0 — no duration chip in the note header, no duration on the sidebar row,
    /// and no docked player (`showsTransport` then falls back to a real file on disk,
    /// which a synced memo hasn't got). Only the demo seeds looked right, which is
    /// exactly why it survived every headless render. Tolerant on READ rather than fixed
    /// at the writer: existing rows already hold both shapes and re-ingest isn't
    /// guaranteed.
    var durationSeconds: Double {
        guard let data = audioMetadataJSON,
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let raw = obj["duration"] else { return 0 }
        return Self.durationSeconds(fromMetadataValue: raw)
    }

    /// The one rule for both shapes. `NSNumber` covers Int and Double alike; a string is
    /// `HH:MM:SS` / `MM:SS` / bare seconds. Anything else — or a negative — is 0.
    static func durationSeconds(fromMetadataValue raw: Any) -> Double {
        if let n = raw as? NSNumber, !(raw is String) {
            let v = n.doubleValue
            return v.isFinite && v > 0 ? v : 0
        }
        guard let s = raw as? String else { return 0 }
        let parts = s.split(separator: ":").map { Double($0) ?? 0 }
        let secs: Double
        switch parts.count {
        case 3:  secs = parts[0] * 3600 + parts[1] * 60 + parts[2]
        case 2:  secs = parts[0] * 60 + parts[1]
        case 1:  secs = parts[0]
        default: return 0
        }
        return secs.isFinite && secs > 0 ? secs : 0
    }

    /// The Mac working folder that holds `images/` + `image_manifest.json` (and the audio):
    /// captures → `path` itself; audio/notes → the parent of `path` (which is `original.<ext>`).
    /// nil when the row has no on-disk path yet. ONE derivation — the review body's `[[img_NNN]]`
    /// resolver, `VaultExporter`, and the CloudKit photo materializer all read it.
    var workingFolder: URL? {
        guard !path.isEmpty else { return nil }
        let url = URL(fileURLWithPath: path)
        return sourceType == .capture ? url : url.deletingLastPathComponent()
    }
}

extension PipelineFile {
    /// The shared rules' source type for this note (`SpeakerTranscript.isConversation(_:source:)`).
    var noteSource: NoteSourceType { NoteSourceType(rawValue: sourceType.rawValue) ?? .audio }

    /// The body as shown and as exported: the name-linked `sanitised`, then the copy-edit, then
    /// the raw transcript. ONE rule for the editor, the split-speakers switch, the Connections
    /// panel and the cloud write-back (it lives here, not in Features, so the host-less test
    /// bundle sees it too). `BatchRunner`'s body-edit guard compares the OPTIONAL chain and
    /// `CompilerBridge` reads a `CompilerInput`; neither uses this.
    var bestBodyText: String { sanitised ?? enhancedCopyedit ?? transcript ?? "" }

    /// Re-link the note's names over `working` and write `sanitised` + `ambiguousNames` (empty
    /// means nil), honouring the note's own name decisions (`unlinkedNames`, `namePicks`).
    /// A conversation takes the turn-aware linker, a monologue the first-mention linker.
    /// The CALLER decides `isConversation` (BatchRunner derives it once from the transcript and
    /// reuses it for tags + copy-edit; the others derive it from `working`), and owns
    /// `sanitiseStatus` and the compile step. Host-less on purpose: no coordinator, no container.
    ///
    /// Both apps decide `isConversation` with `SpeakerTranscript.isConversation` (D175).
    func relinkNames(working: String, isConversation: Bool, people: [Person]) {
        let neverLink = Set(unlinkedNames)
        let result = isConversation
            ? Sanitiser.processConversation(text: working, people: people, neverLink: neverLink, namePicks: namePicks)
            : Sanitiser.process(text: working, people: people, neverLink: neverLink, namePicks: namePicks)
        sanitised = result.sanitised
        ambiguousNames = result.ambiguous.isEmpty ? nil : result.ambiguous
    }
}
