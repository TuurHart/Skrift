import Foundation
import SwiftData

// Desktop bridge to the shared `Compiler` (Skrift_Native/Shared/Export). The pure compiler
// moved to Shared behind the neutral `CompilerInput` so the phone compiles the SAME engine
// (standalone Phase 2). This file keeps the desktop-only pieces:
//   • `PhoneMetadata` — the metadata decode helper several desktop surfaces still use
//     directly (BatchRunner, QueueDerivations, NoteProperties, NoteDisplayView,
//     CaptureViews, tests). It mirrors the PHONE's metadata shape. (`SharedContent`
//     itself is the ONE shared wire struct now — Shared/Model/SharedContent.swift.)
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
            sharedContent: sc.map { .init(type: $0.type.rawValue, url: $0.url, urlTitle: $0.urlTitle, text: $0.text, fileName: $0.fileName) },
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
    /// Desktop convenience — compile straight from a `PipelineFile`. Also supplies the
    /// memo-link resolver (the phone's publish path does the same via `linkStems`): when
    /// the body carries `[[memo:UUID|Title]]` links, they export as `[[<stem>|Title]]`
    /// pointing at the LINKED note's Mac-exported filename instead of degrading to the
    /// title-snapshot fallback. Zero cost for the 99% of notes without links.
    static func compile(file pf: PipelineFile, author: String, date: String? = nil,
                        knownPeople: [Person]? = nil) -> String {
        var input = pf.compilerInput
        let body = input.sanitised ?? input.enhancedCopyedit ?? input.transcript ?? ""
        if !MemoLinkSyntax.occurrences(in: body).isEmpty, let context = pf.modelContext {
            let stems = MemoLinkStems.map(context)
            if !stems.isEmpty { input.memoLinkResolver = { stems[$0] } }   // value capture — Sendable
        }
        return compile(input, author: author, date: date, knownPeople: knownPeople)
    }
}

/// UUID → exported-note stem over the whole queue — what `[[memo:UUID|Title]]` resolves
/// against on the Mac (the phone resolves against ITS published filenames; each sink's
/// links stay self-consistent, and Obsidian resolves `[[stem]]` vault-wide).
enum MemoLinkStems {
    static func map(_ context: ModelContext) -> [UUID: String] {
        let files = (try? context.fetch(FetchDescriptor<PipelineFile>())) ?? []
        var out: [UUID: String] = [:]
        for f in files {
            if let id = UUID(uuidString: f.id) { out[id] = VaultExporter.noteStem(f) }
        }
        return out
    }
}
