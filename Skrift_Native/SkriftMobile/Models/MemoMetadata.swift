import Foundation

/// Contextual metadata captured when a recording stops. Field names and shapes
/// match the RN `MemoMetadata` (`Mobile/lib/metadata.ts`) and the keys the Mac
/// backend reads from the upload `metadata` JSON (`backend/api/files.py`). All
/// timestamps stay as raw ISO/`HH:mm` strings (faithful to the contract; never
/// sorted on in-app), so no JSON date strategy is needed.
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

    /// How the memo entered Skrift, when it's NOT an ordinary voice recording —
    /// the first marker of the deferred "unified source taxonomy" (voice memo /
    /// URL / PDF / video / audiobook quote / Apple Note). Currently set to
    /// `Source.video` for a video import (audio + 1 frame) so the list row can
    /// show a source glyph. ADDITIVE + optional — nil on every ordinary memo, so
    /// the Mac contract stays byte-compatible. A FREE-FORM string (not an enum)
    /// on purpose: a value written by a newer build must never fail to decode on
    /// an older one (which a missing enum case would).
    var sourceType: String?

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
        sourceType: String? = nil
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
        self.sourceType = sourceType
    }

    /// Known `sourceType` values — the first entries of the deferred unified
    /// source taxonomy. Stored as strings (see `sourceType` above).
    enum Source {
        static let video = "video"
    }
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
}

struct DaylightInfo: Codable, Equatable, Sendable {
    /// `HH:mm` local time, matching the RN `formatTime`.
    var sunrise: String
    var sunset: String
    var hoursOfLight: Double
}

/// A timestamped photo taken during recording. `offsetSeconds` is recording
/// time (paused time excluded) and drives `[[img_NNN]]` marker placement.
struct ImageManifestEntry: Codable, Equatable, Sendable {
    var filename: String
    var offsetSeconds: Double
}

// MARK: - Shared content (capture items)

enum ShareContentType: String, Codable, Sendable {
    case url
    case image
    case text
    case file
}

/// A shared URL / image / text / file captured via the Share Extension, with an
/// optional voice or text annotation. Mirrors the RN `SharedContent`.
struct SharedContent: Codable, Equatable, Sendable {
    var type: ShareContentType
    var url: String?
    var urlTitle: String?
    var urlDescription: String?
    var urlThumbnailUrl: String?
    var text: String?
    var filePath: String?
    var fileName: String?
    var mimeType: String?
}
