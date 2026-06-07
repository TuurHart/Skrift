#if DEBUG
import Foundation

/// Test-double engines for UI piloting / XCUITest (behind the `-stubEnhancement`
/// launch arg). They let the Process→Ready flow run instantly with no FluidAudio /
/// MLX download or inference, so interaction testing doesn't pay the 9 GB + minutes
/// cost. NOT used in normal launches. See `ProcessingCoordinator.init`.

/// Returns a canned transcript (overridable with `-seedTranscript <text>`) plus
/// evenly-spaced word timings so karaoke has data to drive.
struct StubTranscriber: Transcribing {
    var text: String
    func transcribe(audioURL: URL, imageManifest: [ImageManifestEntry]) async throws -> TranscriptionResult {
        let words = text.split(whereSeparator: { $0 == " " || $0 == "\n" })
        let timings = words.enumerated().map { i, w in
            WordTiming(word: String(w), start: Double(i) * 0.35, end: Double(i) * 0.35 + 0.30)
        }
        return TranscriptionResult(text: text, confidence: 0.99, durationMs: 5,
                                   wordTimings: timings, markersInjected: false)
    }
}

/// Canned copy-edit (pass-through), title, and summary — no MLX.
struct StubEnhancer: Enhancing {
    func copyEdit(_ transcript: String, prompts: AppSettings.Prompts, modelRepo: String) async throws -> String {
        transcript
    }
    func title(_ transcript: String, prompts: AppSettings.Prompts, modelRepo: String) async throws -> String {
        "Stub — " + transcript.split(separator: " ").prefix(5).joined(separator: " ")
    }
    func summary(_ transcript: String, prompts: AppSettings.Prompts, modelRepo: String) async throws -> String {
        "Stub summary for UI piloting (engines are stubbed)."
    }
}
#endif
