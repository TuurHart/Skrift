import Foundation

/// A diarization result: a time range assigned to a speaker slot (0-based).
/// WIRE CONTRACT: the element of the `diar_<id>.json` sidecar — the phone
/// writes it (`DiarizationStore`) and syncs it as a `MemoAsset` (kind
/// `.diarization`); the Mac decodes the same JSON (`DiarizationSidecar`).
/// Also the input `SpeakerFusion` fuses with the word timings on both apps.
struct DiarizedSegment: Sendable, Equatable, Codable {
    let speaker: Int
    let start: Double
    let end: Double
}
