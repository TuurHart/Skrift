import Foundation

/// One word's timing, driving the karaoke highlight. WIRE CONTRACT: the element
/// of the per-memo `word_timings.json` sidecar — the phone writes it
/// (`WordTimingsStore`) and syncs it as a `MemoAsset` (kind `.wordTimings`); the
/// Mac decodes the same JSON into its per-file sidecar. Field names must never
/// change (they also match the RN-era / Python-backend shape). Kept out of the
/// SwiftData index on both apps — the arrays are large and playback-only.
struct WordTiming: Codable, Equatable, Sendable {
    var word: String
    var start: TimeInterval
    var end: TimeInterval
}
