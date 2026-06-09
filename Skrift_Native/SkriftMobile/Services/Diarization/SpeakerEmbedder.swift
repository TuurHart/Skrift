import Foundation
import FluidAudio

/// Extracts a portable speaker voiceprint — a wespeaker 256-dim embedding — from a clip
/// of ONE speaker's 16kHz-mono audio. This is the identity layer for conversation mode:
/// diarization ("who spoke when", Sortformer) and identification ("is this Tiuri?",
/// embed + `VoiceMatcher` cosine) are separate jobs, because Sortformer can't ingest an
/// embedding. The embedding is what syncs phone↔Mac (`Person.voiceEmbeddings`).
///
/// This is a SECOND on-device model beyond Sortformer (pyannote segmentation + wespeaker
/// embedding, the `DiarizerModels` bundle); first use downloads it (~a minute, then
/// cached) — surfaced via `DiarizationStatus.downloadingVoiceModel`.
protocol SpeakerEmbedding: Sendable {
    /// A 256-dim embedding for a clip of a single speaker (16kHz mono). The caller passes
    /// ≥2s and the impl caps at 10s (the model's fixed window). Throws if too short.
    func embed(samples: [Float]) async throws -> [Float]
    /// Preload the model so a caller can surface the (slow, first-time) download up front.
    func ensureLoaded() async throws
}

enum SpeakerEmbedderError: Error { case notReady, clipTooShort }

/// Real wespeaker embedder via FluidAudio's `DiarizerManager.extractSpeakerEmbedding`
/// (device-only — needs the ANE, like ASR/diarization). The Simulator uses
/// `SeededEmbedder` via `EmbedderFactory`.
actor SpeakerEmbedder: SpeakerEmbedding {
    static let shared = SpeakerEmbedder()

    /// Min clip for a TRUSTWORTHY embedding: under ~2s the spike showed unstable cosines
    /// (0.16–0.49 same-speaker). Max = the wespeaker model's fixed 160k-sample (10s)
    /// waveform window — `EmbeddingExtractor` repeat-pads shorter clips; longer would
    /// overflow the buffer, so the caller must cap.
    static let minSamples = 32_000
    static let maxSamples = 160_000

    private var manager: DiarizerManager?
    private init() {}

    var isModelReady: Bool { manager != nil }

    func ensureLoaded() async throws {
        guard manager == nil else { return }
        let firstTime = !UserDefaults.standard.bool(forKey: "voiceModelReady")
        await MainActor.run { DiarizationStatus.shared.set(firstTime ? .downloadingVoiceModel(nil) : .preparingVoiceModel) }
        let models = try await DiarizerModels.downloadIfNeeded { progress in
            if firstTime { Task { @MainActor in DiarizationStatus.shared.set(.downloadingVoiceModel(progress.fractionCompleted)) } }
        }
        let m = DiarizerManager()
        m.initialize(models: models)
        manager = m
        UserDefaults.standard.set(true, forKey: "voiceModelReady")
    }

    func embed(samples: [Float]) async throws -> [Float] {
        guard samples.count >= Self.minSamples else { throw SpeakerEmbedderError.clipTooShort }
        try await ensureLoaded()
        guard let manager else { throw SpeakerEmbedderError.notReady }
        return try manager.extractSpeakerEmbedding(from: Array(samples.prefix(Self.maxSamples)))
    }
}

enum EmbedderFactory {
    /// Seeded in tests/sim (`-seedTranscript`, which also implies no ANE), real wespeaker
    /// extractor on device otherwise. Mirrors `DiarizerFactory`.
    static func make() -> any SpeakerEmbedding {
        LaunchFlags.seedTranscript != nil ? SeededEmbedder() : SpeakerEmbedder.shared
    }
}

/// Deterministic embedder for UI tests / the sim (no ANE): a stable non-empty 256-dim
/// vector derived from a coarse fingerprint of the clip. It's not a real voiceprint, but
/// it lets naming enroll a (mock) `voiceEmbedding` so the name-once→recognized loop is
/// wireable in the sim; the SeededDiarizer fakes the actual match. Real matching is
/// device-tested.
struct SeededEmbedder: SpeakerEmbedding {
    func ensureLoaded() async throws {}
    func embed(samples: [Float]) async throws -> [Float] {
        // A stable, clip-DEPENDENT 256-dim vector (fold the clip's leading samples into a
        // scalar fingerprint, then spread it across the dims). Distinct clips → distinct
        // vectors, so enroll/union wiring is exercisable; it's not a real voiceprint.
        var acc = 1.0
        for (i, s) in samples.prefix(4000).enumerated() {
            acc = (acc + Double(s) * Double(i + 1)).truncatingRemainder(dividingBy: 100_000)
        }
        return (0..<256).map { Float(sin(acc * 0.0007 + Double($0) * 0.13)) }
    }
}
