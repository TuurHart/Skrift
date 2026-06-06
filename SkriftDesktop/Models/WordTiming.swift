import Foundation

/// One word's timing, written to the per-file `word_timings.json` sidecar and used
/// to drive the karaoke highlight. Mirrors the backend's word-timing shape.
struct WordTiming: Codable, Equatable, Sendable {
    var word: String
    var start: TimeInterval
    var end: TimeInterval
}

/// A timestamped photo taken during a recording. `offsetSeconds` is recording time
/// (paused time excluded) and drives `[[img_NNN]]` marker placement. Matches the
/// phone's `ImageManifestEntry` + the backend `image_manifest.json` entries.
struct ImageManifestEntry: Codable, Equatable, Sendable {
    var filename: String
    var offsetSeconds: Double
}
