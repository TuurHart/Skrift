import Foundation

// Neutral, already-decoded input to the shared `Compiler` — the seam that lets BOTH apps
// compile Obsidian markdown from ONE engine without sharing their storage models (desktop
// `PipelineFile`, mobile `Memo`). Each app maps its own model + metadata into this DTO
// (desktop via `PipelineFile.compilerInput`; mobile via `MemoExporter`), so the Compiler
// stays pure + `PipelineFile`-free → no phone↔Mac drift (standalone Phase 2, hoisted out
// of Phase 0). The type names are deliberately neutral (`Compiler*` / `NoteSourceType`) to
// avoid colliding with each app's own `SharedContent` / metadata types — both apps compile
// this folder into their OWN module, so a clashing name would be a hard build error.

/// Where a note came from. Mirrors the desktop `SourceType` raw values (`audio`/`note`/
/// `capture`) so the desktop bridge maps by `rawValue` and the markdown `source:` key is
/// identical across apps.
enum NoteSourceType: String, Sendable {
    case audio, note, capture
}

/// Sensor / audiobook metadata the Compiler renders into frontmatter — already decoded from
/// whatever blob each app stores (desktop: `PipelineFile.audioMetadataJSON` via
/// `PhoneMetadata`; mobile: `MemoMetadata`). All optional / lenient. Only the fields the
/// Compiler actually reads are carried.
struct CompilerMetadata: Sendable {
    struct Location: Sendable { var placeName: String? = nil }
    struct Weather: Sendable { var conditions: String? = nil; var temperature: Double? = nil; var temperatureUnit: String? = nil }
    struct Pressure: Sendable { var hPa: Double? = nil; var trend: String? = nil }
    struct Daylight: Sendable { var sunrise: String? = nil; var sunset: String? = nil; var hoursOfLight: Double? = nil }
    var location: Location? = nil
    var weather: Weather? = nil
    var pressure: Pressure? = nil
    var dayPeriod: String? = nil
    var daylight: Daylight? = nil
    var steps: Int? = nil
    var recordedAt: String? = nil
    // Audiobook quote-capture (contract C2). Absent on every non-capture memo.
    var bookTitle: String? = nil
    var bookAuthor: String? = nil
    var bookChapter: String? = nil
}

/// The shared-content fields a C3 capture pins above its annotation body. Neutral rename of
/// the desktop decode-helper `SharedContent` (and distinct from mobile's capture-payload
/// `SharedContent`). Only the fields the Compiler reads are carried (no `urlDescription`/
/// `mimeType`). Optionals default to `nil` so partial construction is ergonomic.
struct CompilerSharedContent: Sendable {
    var type: String          // "url" | "text" | "image" | "file"
    var url: String? = nil
    var urlTitle: String? = nil
    var text: String? = nil
    var fileName: String? = nil
}

/// Everything the shared `Compiler.compile(_:)` needs from a note. Each app fills this from
/// its own model; the Compiler never sees `PipelineFile`/`Memo`.
struct CompilerInput: Sendable {
    var filename: String
    var transcript: String? = nil
    var sanitised: String? = nil
    var enhancedCopyedit: String? = nil
    var enhancedTitle: String? = nil
    var enhancedSummary: String? = nil
    var tags: [String] = []
    var significance: Double? = nil
    var sourceType: NoteSourceType = .audio
    var mediaSource: String? = nil
    var metadata: CompilerMetadata? = nil
    var sharedContent: CompilerSharedContent? = nil
    /// Fallback for `recordedAt` when the metadata blob didn't decode into `metadata`
    /// (e.g. a capture's raw dict) — the desktop bridge fills it via `rawMetaString`.
    var rawRecordedAt: String? = nil
}
