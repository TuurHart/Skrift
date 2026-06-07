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

/// A candidate person for an ambiguous alias (alias maps to 2+ people).
struct NameCandidate: Codable, Equatable, Sendable {
    var id: String
    var canonical: String
    var short: String
}

/// An ambiguous alias occurrence carried on the note and resolved at review
/// (non-blocking sanitise). Mirrors the backend `ambiguous_names` entries.
struct AmbiguousOccurrence: Codable, Equatable, Sendable {
    var alias: String
    var offset: Int
    var length: Int
    var contextBefore: String
    var contextAfter: String
    var candidates: [NameCandidate]
}

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

    // Step state as individual enum columns (safe; ProcessingSteps struct is NOT
    // a stored attribute — see the gotcha note above).
    var transcribeStatus: StepStatus = StepStatus.pending
    var sanitiseStatus: StepStatus = StepStatus.pending
    var enhanceStatus: StepStatus = StepStatus.pending
    var exportStatus: StepStatus = StepStatus.pending

    var uploadedAt: Date = Date()
    var lastActivityAt: Date?

    // Transcription / sanitisation
    var transcript: String?
    var sanitised: String?
    /// `[AmbiguousOccurrence]` stored as a JSON blob (struct arrays trap SwiftData).
    var ambiguousNamesJSON: Data?
    /// `[WordTiming]` stored as a JSON blob (the per-file `word_timings.json`
    /// equivalent) — drives the karaoke highlight. Set by the transcribe step.
    var wordTimingsJSON: Data?

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

    /// Decoded ambiguous-name occurrences (backed by `ambiguousNamesJSON`).
    var ambiguousNames: [AmbiguousOccurrence]? {
        get { ambiguousNamesJSON.flatMap { try? JSONDecoder().decode([AmbiguousOccurrence].self, from: $0) } }
        set { ambiguousNamesJSON = newValue.flatMap { try? JSONEncoder().encode($0) } }
    }

    /// Per-word transcript timings (backed by `wordTimingsJSON`) — drives karaoke.
    var wordTimings: [WordTiming] {
        get { wordTimingsJSON.flatMap { try? JSONDecoder().decode([WordTiming].self, from: $0) } ?? [] }
        set { wordTimingsJSON = newValue.isEmpty ? nil : (try? JSONEncoder().encode(newValue)) }
    }
}
