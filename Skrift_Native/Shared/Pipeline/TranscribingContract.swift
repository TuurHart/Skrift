import AVFoundation
import Foundation

// The transcription seam, ONE copy for both apps (SharedKit wave 2; previously
// twinned mobile TranscriptionService.swift vs desktop Transcribing.swift).
// Pure code — the FluidAudio engines conform from each app's engine layer;
// tests + UI drive stubs/seeded transcribers.

/// Result of transcribing one file. `text` carries `[[img_NNN]]` markers when a
/// photo manifest was supplied; `wordTimings` feed the per-file sidecar + karaoke.
struct TranscriptionResult: Sendable {
    let text: String
    let confidence: Double
    let durationMs: Int
    let wordTimings: [WordTiming]
    let markersInjected: Bool
}

/// Transcription seam: the real FluidAudio engine (each app's
/// `TranscriptionService`) conforms; tests + UI use a stub/seeded transcriber.
protocol Transcribing: Sendable {
    func transcribe(audioURL: URL, imageManifest: [ImageManifestEntry]) async throws -> TranscriptionResult
    /// Transcribe raw PCM directly — the whole-book chunk path (phone). No
    /// temp-file round-trip, no image markers, and no custom-vocab rescore.
    /// A REQUIREMENT (with a spill-to-WAV default below) so a conformer's
    /// native buffer path dispatches through `any Transcribing`.
    func transcribe(buffer: AVAudioPCMBuffer) async throws -> TranscriptionResult
}

extension Transcribing {
    func transcribe(audioURL: URL) async throws -> TranscriptionResult {
        try await transcribe(audioURL: audioURL, imageManifest: [])
    }

    /// Default: spill to a temp WAV and take the file path — for conformers
    /// without a native buffer path (stubs, seeded/test transcribers, the Mac).
    func transcribe(buffer: AVAudioPCMBuffer) async throws -> TranscriptionResult {
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("bufferspill_\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: temp) }
        try Self.writeWAV(buffer, to: temp)
        return try await transcribe(audioURL: temp, imageManifest: [])
    }

    /// Write `buffer` to `url` as WAV. A standalone function so the writing
    /// `AVAudioFile` deallocates (and flushes) on return, before anyone reads it.
    private static func writeWAV(_ buffer: AVAudioPCMBuffer, to url: URL) throws {
        try? FileManager.default.removeItem(at: url)
        let out = try AVAudioFile(forWriting: url, settings: buffer.format.settings)
        try out.write(from: buffer)
    }
}
