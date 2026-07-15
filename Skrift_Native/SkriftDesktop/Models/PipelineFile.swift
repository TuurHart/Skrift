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
    /// Canonical keys (bare names, no brackets) the user chose to UNLINK everywhere
    /// in this note ("Unlink all mentions in this note", mocks/name-unlink.html).
    /// Fed back into `Sanitiser.process(neverLink:)` so re-processing never re-links
    /// them HERE — the person stays in the names DB and links normally elsewhere.
    /// Primitive `[String]` is safe to store directly (see the gotcha above).
    var unlinkedNames: [String] = []
    /// Per-note "which person?" picks (NAMING_MODEL.md decision 9 — the ambiguity-pick
    /// record): alias (lowercased) → the chosen person's canonical `[[Name]]`. Set when the
    /// user resolves a dotted SUGGESTION in review — an ambiguous twin ("which Jack?") or a
    /// common-word confirmation ("Will" → Will Smith) — so the deterministic re-link
    /// force-links that alias to that person for THIS note and a re-process remembers the
    /// choice (decision 9: note-level pick). Stored as a JSON blob (a dictionary traps
    /// SwiftData — see the gotcha above); empty by default. Consumed by the Sanitiser in
    /// chunk 4 (the in-prose popover writes it). Replaced the opt-in `aboutPeople` include-list.
    var namePicksJSON: Data?
    /// `[WordTiming]` stored as a JSON blob (the per-file `word_timings.json`
    /// equivalent) — drives the karaoke highlight. Set by the transcribe step.
    var wordTimingsJSON: Data?
    /// `[DiarizedSegment]` stored as a JSON blob (the per-file `diar_<id>.json`
    /// sidecar equivalent). Persisted by the conversation-mode diarize step so a
    /// speaker's audio can be re-extracted later — to ENROLL their voice from the Mac
    /// review screen — WITHOUT re-diarizing. Empty for monologues / phone-attributed
    /// memos the Mac never split. (Set alongside the `diar_<id>.json` sidecar.)
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

    /// Soft-delete — "Recently Deleted", mirroring the phone + Apple Voice Memos.
    /// A trashed file (`deletedAt != nil`) is hidden from the sidebar/queue,
    /// excluded from the phone's `GET /api/files/` list, and never processed; its
    /// on-disk working folder STAYS so Restore is lossless. The launch purge
    /// removes the record (+ trashes the folder) once `DesktopTrashPolicy.retention`
    /// old. Additive + optional → existing stores migrate lightweight.
    var deletedAt: Date?

    /// Whole days left before the launch purge removes a trashed file for good.
    func trashDaysRemaining(now: Date = Date()) -> Int {
        guard let deletedAt else { return DesktopTrashPolicy.retentionDays }
        let elapsed = now.timeIntervalSince(deletedAt)
        return max(0, DesktopTrashPolicy.retentionDays - Int(elapsed / 86_400))
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

    /// Convenience view over the four step columns.
    var steps: ProcessingSteps {
        get {
            ProcessingSteps(transcribe: transcribeStatus, sanitise: sanitiseStatus,
                            enhance: enhanceStatus, export: exportStatus)
        }
        set {
            transcribeStatus = newValue.transcribe
            sanitiseStatus = newValue.sanitise
            enhanceStatus = newValue.enhance
            exportStatus = newValue.export
        }
    }

    /// Decoded ambiguous-name occurrences (backed by `ambiguousNamesJSON`). In the OPT-OUT
    /// model these are the *suggested* tier — recognised-but-not-auto-linked occurrences
    /// (ambiguous twins + common-word names) the review surface renders dotted (chunk 4).
    var ambiguousNames: [AmbiguousOccurrence]? {
        get { ambiguousNamesJSON.flatMap { try? JSONDecoder().decode([AmbiguousOccurrence].self, from: $0) } }
        set { ambiguousNamesJSON = newValue.flatMap { try? JSONEncoder().encode($0) } }
    }

    /// Decoded per-note "which person?" picks (backed by `namePicksJSON`) — alias
    /// (lowercased) → chosen canonical `[[Name]]`. The ambiguity-pick record (decision 9).
    var namePicks: [String: String] {
        get { namePicksJSON.flatMap { try? JSONDecoder().decode([String: String].self, from: $0) } ?? [:] }
        set { namePicksJSON = newValue.isEmpty ? nil : (try? JSONEncoder().encode(newValue)) }
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
              let meta = try? JSONDecoder().decode(PhoneMetadata.self, from: data),
              let title = BookCapture.trimmedNonEmpty(meta.bookTitle) else { return nil }
        return BookCapture(title: title,
                           author: BookCapture.trimmedNonEmpty(meta.bookAuthor),
                           chapter: BookCapture.trimmedNonEmpty(meta.bookChapter))
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
        var s = "— "
        if let author { s += "\(author), " }
        s += title
        if let chapter {
            s += " · " + (chapter.allSatisfy(\.isNumber) ? "ch. \(chapter)" : chapter)
        }
        return s
    }

    /// Char ranges (NSString/UTF-16 coords) of the leading C1 blockquote lines —
    /// the consecutive ">"-prefixed lines from offset 0, exactly the block
    /// `QuoteProtection.splitLeadingQuote` byte-protects through enhancement.
    /// Empty when the text doesn't open with ">". Drives the editor's quote
    /// styling + attribution-caption placement (presentation only — the stored
    /// text keeps the raw "> " lines).
    static func quoteLineRanges(in text: String) -> [NSRange] {
        guard let split = QuoteProtection.splitLeadingQuote(text) else { return [] }
        var ranges: [NSRange] = []
        var loc = 0
        for line in split.quote.components(separatedBy: "\n") {
            let len = (line as NSString).length
            ranges.append(NSRange(location: loc, length: len))
            loc += len + 1   // + the "\n" the join dropped
        }
        return ranges
    }

    static func trimmedNonEmpty(_ v: String?) -> String? {
        guard let t = v?.trimmingCharacters(in: .whitespaces), !t.isEmpty else { return nil }
        return t
    }
}

extension PipelineFile {
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
