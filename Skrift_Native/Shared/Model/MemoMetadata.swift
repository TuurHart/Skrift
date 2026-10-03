import Foundation

/// Contextual metadata captured when a recording stops — the SCHEMA of
/// `Memo.metadataData` (persisted as a JSON blob, synced over CloudKit). ONE
/// shared definition: the phone writes it, the Mac reads it (typed via
/// `Memo.metadata`; `MemoMetadata.Lenient` below (the Mac's `PhoneMetadata`) is
/// the deliberately-lenient reader for LEGACY working-folder payloads from
/// the RN/Python era). Field names and shapes are the wire contract — they
/// match the RN `MemoMetadata` (`archive/Mobile/lib/metadata.ts`) and the keys
/// the old backend read (`archive/backend/api/files.py`); never rename them.
/// All timestamps stay as raw ISO/`HH:mm` strings (faithful to the contract;
/// never sorted on in-app), so no JSON date strategy is needed.
struct MemoMetadata: Codable, Equatable, Sendable {
    var capturedAt: String?
    var location: LocationInfo?
    var weather: WeatherInfo?
    var pressure: PressureInfo?
    var dayPeriod: DayPeriod?
    var daylight: DaylightInfo?
    var steps: Int?
    var tags: [String]
    var photoFilename: String?
    var imageManifest: [ImageManifestEntry]?
    /// Audiobook quote-capture (CROSS-LANE CONTRACT C2): the source book's
    /// title / author / chapter NUMBER ("4"), riding the existing metadata JSON
    /// to the Mac. ADDITIVE + optional — absent on every non-capture memo, so
    /// the contract stays byte-compatible. The Mac composes the export
    /// attribution ("— [[Author]], *Book*, ch. N") from these; the phone never
    /// writes `[[..]]` or an attribution line.
    var bookTitle: String?
    var bookAuthor: String?
    var bookChapter: String?
    /// STABLE link back to the source audiobook (2026-07-06): the library
    /// `Audiobook.id` + the quote's GLOBAL book position (seconds). The
    /// title/author strings above break as a join key the moment the user edits
    /// book details — these don't, and they're what any "notes for this book" /
    /// jump-back-to-the-spot surface needs. ADDITIVE + optional (absent on
    /// pre-existing captures and every non-capture memo; unknown keys are
    /// ignored by the Mac's decoder) — contract stays byte-compatible.
    var bookID: UUID?
    var bookPosition: Double?

    /// How the memo entered Skrift, when it's NOT an ordinary voice recording —
    /// the first marker of the deferred "unified source taxonomy" (voice memo /
    /// URL / PDF / video / audiobook quote / Apple Note). Currently set to
    /// `Source.video` for a video import (audio + 1 frame) so the list row can
    /// show a source glyph. ADDITIVE + optional — nil on every ordinary memo, so
    /// the Mac contract stays byte-compatible. A FREE-FORM string (not an enum)
    /// on purpose: a value written by a newer build must never fail to decode on
    /// an older one (which a missing enum case would).
    var sourceType: String?

    /// C124 / D35: a merged multi-clip note keeps where each clip starts in the merged audio and
    /// its own message time. ADDITIVE + optional (nil on every other memo; unknown keys are ignored
    /// by an older decoder). The body never shows the times, only the paragraph break each start forces.
    var clipManifest: [ClipManifestEntry]?

    init(
        capturedAt: String? = nil,
        location: LocationInfo? = nil,
        weather: WeatherInfo? = nil,
        pressure: PressureInfo? = nil,
        dayPeriod: DayPeriod? = nil,
        daylight: DaylightInfo? = nil,
        steps: Int? = nil,
        tags: [String] = [],
        photoFilename: String? = nil,
        imageManifest: [ImageManifestEntry]? = nil,
        bookTitle: String? = nil,
        bookAuthor: String? = nil,
        bookChapter: String? = nil,
        bookID: UUID? = nil,
        bookPosition: Double? = nil,
        sourceType: String? = nil,
        clipManifest: [ClipManifestEntry]? = nil
    ) {
        self.capturedAt = capturedAt
        self.location = location
        self.weather = weather
        self.pressure = pressure
        self.dayPeriod = dayPeriod
        self.daylight = daylight
        self.steps = steps
        self.tags = tags
        self.photoFilename = photoFilename
        self.imageManifest = imageManifest
        self.bookTitle = bookTitle
        self.bookAuthor = bookAuthor
        self.bookChapter = bookChapter
        self.bookID = bookID
        self.bookPosition = bookPosition
        self.sourceType = sourceType
        self.clipManifest = clipManifest
    }

    /// Known `sourceType` values — the first entries of the deferred unified
    /// source taxonomy. Stored as strings (see `sourceType` above).
    enum Source {
        static let video = "video"
        /// A Mac picture-only import (no sharedContent): reads "Image" like a phone image share (Q179).
        static let image = "image"
    }
}

extension MemoMetadata {
    /// The LENIENT reader of the same blob (Q172, books-102; was the Mac's `PhoneMetadata`
    /// in CompilerBridge.swift). Every field optional and loosely typed (temperature and
    /// hPa as Double, dayPeriod as a string, location without coordinates), so a legacy
    /// RN/Python-era payload or a partial one still yields what it has instead of nil —
    /// the strict `MemoMetadata` decoder refuses those (no `tags`, no lat/long). Reads only
    /// the frontmatter fields; `bookID`/`bookPosition` are ignored (FEATURES.md "ignore").
    /// Encodes absent fields as absent (synthesized encodeIfPresent).
    struct Lenient: Codable, Sendable {
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
        // older phone builds, so the contract stays byte-compatible in both directions.
        var bookTitle: String?
        var bookAuthor: String?
        var bookChapter: String?
    }

    /// The ONE lenient decode of a metadata blob: nil for no blob or unreadable JSON.
    static func lenient(from data: Data?) -> Lenient? {
        data.flatMap { try? JSONDecoder().decode(Lenient.self, from: $0) }
    }
}

/// One clip's place in a merged multi-clip note (C124, D35): where its speech STARTS in the
/// merged audio and its own message time. Lives with the metadata schema because the phone
/// syncs it in `MemoMetadata.clipManifest`; the Mac writes the same shape to `clip_manifest.json`
/// beside the merged audio. The body never shows `recordedAt`.
struct ClipManifestEntry: Codable, Equatable, Sendable {
    var filename: String
    var startSeconds: Double
    /// The clip's own message time (C70 ladder), ISO-8601; nil when its name carries none.
    var recordedAt: String?
}

struct LocationInfo: Codable, Equatable, Sendable {
    var latitude: Double
    var longitude: Double
    var placeName: String?
}

struct WeatherInfo: Codable, Equatable, Sendable {
    var conditions: String
    var temperature: Int
    var temperatureUnit: String
}

/// NOTE (2026-07-26 audit): `hPa` is deliberately `Int` here and `Double?` in the two
/// export-side shapes (`CompilerMetadata.Pressure`, `PhoneMetadata.Pressure`). That is
/// NOT drift to "fix": this struct is the SYNCED Codable contract, so widening it makes
/// new writes emit `1013.0`, which every older build fails to decode into `Int` — a wire
/// break across both apps, for sub-hPa precision nothing displays. `WeatherClient` rounds
/// on the way in; `MemoExporter` widens on the way out. Leave the storage type alone.
struct PressureInfo: Codable, Equatable, Sendable {
    var hPa: Int
    var trend: PressureTrend
}

enum PressureTrend: String, Codable, Sendable {
    case rising
    case steady
    case falling
}

enum DayPeriod: String, Codable, Sendable {
    case morning
    case afternoon
    case evening
    case night

    /// SF Symbol + label for the context chip — SHARED so the phone header and the
    /// Mac properties can't drift on how a daypart reads.
    var symbol: String {
        switch self {
        case .morning: return "sunrise.fill"
        case .afternoon: return "sun.max.fill"
        case .evening: return "sunset.fill"
        case .night: return "moon.stars.fill"
        }
    }
    var label: String { rawValue.capitalized }
}

struct DaylightInfo: Codable, Equatable, Sendable {
    /// `HH:mm` local time, matching the RN `formatTime`.
    var sunrise: String
    var sunset: String
    var hoursOfLight: Double
}

/// A timestamped photo taken during recording. `offsetSeconds` is recording
/// time (paused time excluded) and drives `[[img_NNN]]` marker placement.
/// Also the element of the Mac's per-file `image_manifest.json` sidecar.
struct ImageManifestEntry: Codable, Equatable, Sendable {
    var filename: String
    var offsetSeconds: Double
    /// On-device OCR of the photo (NFeat chunk 6): nil = not indexed yet,
    /// "" = indexed and no text found. Additive — old payloads decode fine,
    /// and it rides the synced metadata blob to every device.
    var text: String? = nil
}
