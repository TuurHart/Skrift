import Foundation
import FluidAudio

/// Diarization result: speaker time-ranges + the matched name per slot (Sortformer
/// labels a slot when its voice matches an enrolled person; nil otherwise).
struct DiarizationOutput: Sendable {
    let segments: [DiarizedSegment]
    let slotNames: [Int: String]
}

/// Splits a recording into speakers. Real impl = NVIDIA Sortformer via FluidAudio (ANE,
/// device-only); a seeded mock backs the sim (no ANE, same as ASR). See `SpeakerFusion`
/// for turning the output into the `**Name:**` transcript.
protocol Diarizing: Sendable {
    func diarize(audioURL: URL) async throws -> DiarizationOutput
}

enum DiarizationError: Error { case notReady }

/// Sortformer-backed diarizer. Chosen over the legacy pyannote `DiarizerManager` (best
/// pre-enrolled speaker mapping, stable IDs, similar-voice handling) — see the handoff +
/// DiarizeSpike. Default config (no clusteringThreshold games). Before diarizing it
/// enrolls every known voice (`SpeakerVoiceStore`) so returning speakers come back named.
actor DiarizationService: Diarizing {
    static let shared = DiarizationService()

    private let config = SortformerConfig.default
    private var diarizer: SortformerDiarizer?
    private let voices = SpeakerVoiceStore()
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

    func diarize(audioURL: URL) async throws -> DiarizationOutput {
        try await ensureLoaded()
        await MainActor.run { DiarizationStatus.shared.set(.identifying) }
        guard let diarizer else { throw DiarizationError.notReady }

        // Pre-enroll known voices (fresh state first) so matching slots come back named.
        diarizer.reset()
        for v in voices.allKnown() where v.samples.count >= 8000 {
            try? diarizer.enrollSpeaker(withAudio: v.samples, named: v.name)
        }

        let samples = try AudioConverter(sampleRate: 16000).resampleAudioFile(audioURL)
        let timeline = try diarizer.processComplete(samples)

        var segments: [DiarizedSegment] = []
        var slotNames: [Int: String] = [:]
        for (slot, speaker) in timeline.speakers {
            for s in speaker.finalizedSegments {
                segments.append(DiarizedSegment(speaker: slot, start: Double(s.startTime), end: Double(s.endTime)))
            }
            if let name = speaker.name, !name.isEmpty { slotNames[slot] = name }
        }
        return DiarizationOutput(segments: segments.sorted { $0.start < $1.start }, slotNames: slotNames)
    }
}

enum DiarizerFactory {
    /// Seeded in tests/sim (`-seedTranscript`, which also implies no ANE), real
    /// Sortformer engine on device otherwise.
    static func make() -> any Diarizing {
        LaunchFlags.seedTranscript != nil ? SeededDiarizer() : DiarizationService.shared
    }
}

/// Deterministic diarizer for UI tests / the sim (no ANE): alternating `speakers`
/// blocks, and — to exercise the name-once→recognized loop — labels slots with any
/// already-enrolled voices (simulating Sortformer's auto-match).
struct SeededDiarizer: Diarizing {
    var speakers = 2
    var blockSeconds = 4.0
    var totalSeconds = 28.0

    func diarize(audioURL: URL) async throws -> DiarizationOutput {
        var segs: [DiarizedSegment] = []
        var t = 0.0, i = 0
        while t < totalSeconds {
            segs.append(DiarizedSegment(speaker: i % speakers, start: t, end: min(t + blockSeconds, totalSeconds)))
            t += blockSeconds; i += 1
        }
        let known = SpeakerVoiceStore().knownNames().sorted()
        var slotNames: [Int: String] = [:]
        for slot in 0..<speakers where slot < known.count { slotNames[slot] = known[slot] }
        return DiarizationOutput(segments: segs, slotNames: slotNames)
    }
}
