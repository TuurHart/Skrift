import Foundation

// Desktop bridge to the shared `Compiler` (Skrift_Native/Shared/Export). The pure compiler
// moved to Shared behind the neutral `CompilerInput` so the phone compiles the SAME engine
// (standalone Phase 2). This file keeps the desktop-only pieces:
//   • `PhoneMetadata` / `SharedContent` — the decode helpers several desktop surfaces still
//     use directly (BatchRunner, QueueDerivations, NoteProperties, NoteDisplayView,
//     CaptureViews, tests). They mirror the PHONE's metadata shape and stay desktop-side
//     (mobile already has its own `SharedContent`, so they can't move to Shared).
//   • `PipelineFile.compilerInput` — maps a queue item into the neutral DTO.
//   • `Compiler.compile(file:)` — byte-identical shim so every existing call site is unchanged.

/// Phone-sent metadata, decoded from `PipelineFile.audioMetadataJSON` (the phone's
/// MemoMetadata shape) for the export frontmatter. All optional / lenient.
struct PhoneMetadata: Codable, Sendable {
    struct Location: Codable, Sendable { var placeName: String? }
    struct Weather: Codable, Sendable { var conditions: String?; var temperature: Double?; var temperatureUnit: String? }
    struct Pressure: Codable, Sendable { var hPa: Double?; var trend: String? }
    struct Daylight: Codable, Sendable { var sunrise: String?; var sunset: String?; var hoursOfLight: Double? }
    var location: Location?
    var weather: Weather?
    var pressure: Pressure?
    var dayPeriod: String?
    var daylight: Daylight?
    var steps: Int?
    var recordedAt: String?
    // Audiobook quote-capture (contract C2) — additive optional fields riding the
    // existing metadata JSON. Absent on every non-capture memo and on uploads from
    // older phone builds (synthesized Codable = decodeIfPresent / encodeIfPresent),
    // so the contract stays byte-compatible in both directions.
    var bookTitle: String?
    var bookAuthor: String?
    var bookChapter: String?
}

/// The `sharedContent` object from `PipelineFile.audioMetadataJSON` for C3 captures.
/// Mirrors mobile's `SharedContent` Codable — field names are intentionally identical.
/// Decoded on-demand (not stored on PipelineFile — avoids the SwiftData Codable trap).
struct SharedContent: Codable, Sendable {
    var type: String          // "url" | "text" | "image" | "file"
    var url: String?          // url captures
    var urlTitle: String?     // url captures (from share payload, no network fetch)
    var urlDescription: String?
    var text: String?         // text captures (the quoted snippet)
    var fileName: String?     // image captures (the image part's filename)
    var mimeType: String?     // image captures

    /// Decode from the raw metadata JSON blob.
    static func decode(from metadataJSON: Data?) -> SharedContent? {
        guard let data = metadataJSON else { return nil }
        // Try Codable first (standard JSON keys), then fall back to manual extraction
        // (the demo seeds use a raw dict with snake_case `shared_content` key).
        if let wrapper = try? JSONDecoder().decode(_Wrapper.self, from: data) { return wrapper.sharedContent }
        if let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
           let sc = (obj["sharedContent"] ?? obj["shared_content"]) as? [String: Any] {
            return SharedContent(
                type: sc["type"] as? String ?? "",
                url: sc["url"] as? String,
                urlTitle: sc["urlTitle"] as? String,
                urlDescription: sc["urlDescription"] as? String,
                text: sc["text"] as? String,
                fileName: sc["fileName"] as? String,
                mimeType: sc["mimeType"] as? String
            )
        }
        return nil
    }

    private struct _Wrapper: Codable { var sharedContent: SharedContent? }
}

extension PipelineFile {
    /// Map this queue item into the neutral `CompilerInput` the shared `Compiler` consumes.
    /// Decodes the metadata blob through the desktop `PhoneMetadata`/`SharedContent` helpers
    /// exactly as the pre-Shared `Compiler.compile` did, so output stays byte-identical.
    var compilerInput: CompilerInput {
        let meta = audioMetadataJSON.flatMap { try? JSONDecoder().decode(PhoneMetadata.self, from: $0) }
        let sc = SharedContent.decode(from: audioMetadataJSON)
        return CompilerInput(
            filename: filename,
            transcript: transcript,
            sanitised: sanitised,
            enhancedCopyedit: enhancedCopyedit,
            enhancedTitle: enhancedTitle,
            enhancedSummary: enhancedSummary,
            tags: tags,
            significance: significance,
            sourceType: NoteSourceType(rawValue: sourceType.rawValue) ?? .audio,
            mediaSource: mediaSource,
            metadata: meta.map { m in
                CompilerMetadata(
                    location: m.location.map { .init(placeName: $0.placeName) },
                    weather: m.weather.map { .init(conditions: $0.conditions, temperature: $0.temperature, temperatureUnit: $0.temperatureUnit) },
                    pressure: m.pressure.map { .init(hPa: $0.hPa, trend: $0.trend) },
                    dayPeriod: m.dayPeriod,
                    daylight: m.daylight.map { .init(sunrise: $0.sunrise, sunset: $0.sunset, hoursOfLight: $0.hoursOfLight) },
                    steps: m.steps,
                    recordedAt: m.recordedAt,
                    bookTitle: m.bookTitle,
                    bookAuthor: m.bookAuthor,
                    bookChapter: m.bookChapter
                )
            },
            sharedContent: sc.map { .init(type: $0.type, url: $0.url, urlTitle: $0.urlTitle, text: $0.text, fileName: $0.fileName) },
            rawRecordedAt: Self.rawMetaString(audioMetadataJSON, key: "recordedAt")
        )
    }

    /// Extract a top-level string from the raw metadata JSON without Codable (for keys
    /// PhoneMetadata doesn't have — e.g. `recordedAt` on captures).
    static func rawMetaString(_ data: Data?, key: String) -> String? {
        guard let data,
              let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let v = obj[key] as? String else { return nil }
        return v
    }
}

extension Compiler {
    /// Desktop convenience — compile straight from a `PipelineFile`. Byte-identical to the
    /// pre-Shared `compile(file:)`, so every desktop call site is unchanged.
    static func compile(file pf: PipelineFile, author: String, date: String? = nil,
                        knownPeople: [Person]? = nil) -> String {
        compile(pf.compilerInput, author: author, date: date, knownPeople: knownPeople)
    }
}
