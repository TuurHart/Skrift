import Foundation

/// Result of transcribing one file. `text` carries `[[img_NNN]]` markers when a
/// photo manifest was supplied; `wordTimings` feed the per-file sidecar + karaoke.
/// Lives in pure code (not Engines/) so the protocol + orchestration host-test
/// without FluidAudio.
struct TranscriptionResult: Sendable {
    let text: String
    let confidence: Double
    let durationMs: Int
    let wordTimings: [WordTiming]
    let markersInjected: Bool
}

/// Transcription seam: the real FluidAudio engine (`TranscriptionService`) conforms;
/// tests + UI use a stub/seeded transcriber.
protocol Transcribing: Sendable {
    func transcribe(audioURL: URL, imageManifest: [ImageManifestEntry]) async throws -> TranscriptionResult
}

extension Transcribing {
    func transcribe(audioURL: URL) async throws -> TranscriptionResult {
        try await transcribe(audioURL: audioURL, imageManifest: [])
    }
}
