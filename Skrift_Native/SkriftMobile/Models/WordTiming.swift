import Foundation

/// Word-level timing for karaoke playback. Mirrors the RN `WordTiming`. Stored
/// in a per-memo sidecar (`WordTimingsStore`), never in the SwiftData index —
/// these arrays are large and only needed for playback, so keeping them out of
/// the index keeps memo queries cheap (the overhaul's memory win).
struct WordTiming: Codable, Equatable, Sendable {
    var word: String
    var start: Double
    var end: Double
}
