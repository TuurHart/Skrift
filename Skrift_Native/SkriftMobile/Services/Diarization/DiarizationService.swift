import Foundation
import FluidAudio

/// Splits a recording into speaker segments. Real implementation = NVIDIA Sortformer
/// via FluidAudio (ANE, device-only); a seeded mock backs the sim (no ANE there, same
/// as ASR). See `SpeakerFusion` for turning these segments + word-timings into the
/// `**Name:**` transcript.
protocol Diarizing: Sendable {
    func diarize(audioURL: URL) async throws -> [DiarizedSegment]
}

enum DiarizationError: Error { case notReady }

/// Sortformer-backed diarizer. Chosen over the legacy pyannote `DiarizerManager` (best
/// pre-enrolled speaker mapping, stable IDs, similar-voice handling, streaming) — see
/// the handoff + DiarizeSpike. `clusteringThreshold` games are NOT needed; the default
/// config splits real conversations correctly (validated on the user's memo).
actor DiarizationService: Diarizing {
    static let shared = DiarizationService()

    private let config = SortformerConfig.default
    private var diarizer: SortformerDiarizer?
    private init() {}

    var isModelReady: Bool { diarizer != nil }

    /// Download + load the Sortformer CoreML bundle once (≈12 files; first compile is
    /// slow, then cached). Device-only in practice (ANE).
    func ensureLoaded() async throws {
        guard diarizer == nil else { return }
        await MainActor.run { DiarizationStatus.shared.set(.downloadingModel(nil)) }
        let models = try await SortformerModels.loadFromHuggingFace(config: config) { progress in
            Task { @MainActor in DiarizationStatus.shared.set(.downloadingModel(progress.fractionCompleted)) }
        }
        let d = SortformerDiarizer(config: config)
        d.initialize(models: models)
        diarizer = d
    }

    func diarize(audioURL: URL) async throws -> [DiarizedSegment] {
        try await ensureLoaded()
        await MainActor.run { DiarizationStatus.shared.set(.identifying) }
        guard let diarizer else { throw DiarizationError.notReady }
        let samples = try AudioConverter(sampleRate: 16000).resampleAudioFile(audioURL)
        let timeline = try diarizer.processComplete(samples)
        var segments: [DiarizedSegment] = []
        for (slot, speaker) in timeline.speakers {
            for s in speaker.finalizedSegments {
                segments.append(DiarizedSegment(speaker: slot, start: Double(s.startTime), end: Double(s.endTime)))
            }
        }
        return segments.sorted { $0.start < $1.start }
    }

    /// Diarize + fuse with the ASR word-timings → the `**Name:**` conversation transcript.
    func attributedTranscript(
        audioURL: URL, words: [WordTiming], name: @escaping (Int) -> String = { "Speaker \($0 + 1)" }
    ) async throws -> String {
        let segments = try await diarize(audioURL: audioURL)
        return SpeakerFusion.attributedTranscript(words: words, segments: segments, name: name)
    }
}

enum DiarizerFactory {
    /// Seeded in tests/sim (`-seedTranscript`, which also implies no ANE), real
    /// Sortformer engine on device otherwise.
    static func make() -> any Diarizing {
        LaunchFlags.seedTranscript != nil ? SeededDiarizer() : DiarizationService.shared
    }
}

/// Deterministic diarizer for UI tests / the sim (no ANE): splits the timeline evenly
/// into `speakers` alternating blocks of `blockSeconds`.
struct SeededDiarizer: Diarizing {
    var speakers = 2
    var blockSeconds = 4.0
    var totalSeconds = 28.0

    func diarize(audioURL: URL) async throws -> [DiarizedSegment] {
        var segs: [DiarizedSegment] = []
        var t = 0.0, i = 0
        while t < totalSeconds {
            segs.append(DiarizedSegment(speaker: i % speakers, start: t, end: min(t + blockSeconds, totalSeconds)))
            t += blockSeconds; i += 1
        }
        return segs
    }
}
