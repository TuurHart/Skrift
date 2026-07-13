import Foundation

// `DiarizedSegment` is the shared wire-contract struct (Shared/Model/DiarizedSegment.swift).

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

// `SpeakerTranscript` (turn parsing/merging — the shared Sanitiser parses through it)
// is the shared type: Shared/Pipeline/SpeakerTranscript.swift.
