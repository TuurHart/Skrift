import Foundation

/// A diarization result: a time range assigned to a speaker slot (0-based).
struct DiarizedSegment: Sendable, Equatable, Codable {
    let speaker: Int
    let start: Double
    let end: Double
}

/// Diarization result: speaker time-ranges + the matched name per slot (a slot is named
/// when its voiceprint cosine-matches a known person; nil otherwise → "Speaker N").
struct DiarizationOutput: Sendable {
    let segments: [DiarizedSegment]
    let slotNames: [Int: String]
}

/// Splits a recording into speakers ("who spoke when") + matches each to a known voice
/// ("is this Tiuri?"). Real impl = Sortformer + wespeaker via FluidAudio (`Engines/`,
/// app-only, device ANE); the pipeline injects it so `BatchRunner` host-tests with a stub
/// or no diarizer. Mirrors the phone's `Diarizing`.
protocol Diarizing: Sendable {
    func diarize(audioURL: URL) async throws -> DiarizationOutput
}

/// Detects whether a transcript is already speaker-attributed (`**Name:**` turns), so the
/// Mac doesn't re-diarize a conversation the phone already split.
enum SpeakerTranscript {
    /// True when `transcript` has ≥2 `**Name:**` turn prefixes.
    static func isAttributed(_ transcript: String?) -> Bool {
        guard let t = transcript,
              let re = try? NSRegularExpression(pattern: #"\*\*([^*\n]+?):\*\*[ \t]*"#) else { return false }
        return re.numberOfMatches(in: t, range: NSRange(location: 0, length: (t as NSString).length)) >= 2
    }
}
