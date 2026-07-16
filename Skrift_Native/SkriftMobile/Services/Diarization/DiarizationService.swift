import Foundation
import FluidAudio

// `DiarizationOutput` + the `Diarizing` protocol + the pure clip/identify/cluster
// passes are SHARED (Shared/Pipeline/DiarizingContract.swift) — this file keeps
// only the FluidAudio engine binding (Sortformer + wespeaker) and its status UI.

enum DiarizationError: Error { case notReady }

/// Sortformer-backed diarizer ("who spoke when"), chosen over the legacy pyannote
/// `DiarizerManager` for diarization (best splits, stable IDs — see the handoff +
/// DiarizeSpike; default config, no clusteringThreshold games).
///
/// IDENTIFICATION ("is this Tiuri?") is a SEPARATE step: Sortformer can't ingest a
/// voiceprint, so after diarizing we embed each speaker's audio (`SpeakerEmbedder`,
/// wespeaker) and cosine-match it against the known people's `voiceEmbeddings`
/// (`VoiceMatcher`). The embedding is the portable identity that syncs phone↔Mac — not a
/// device-local audio sample. Matching is skipped entirely when no voices are enrolled.
actor DiarizationService: Diarizing {
    static let shared = DiarizationService()

    private let config = SortformerConfig.default
    private var diarizer: SortformerDiarizer?
    private let embedder = SpeakerEmbedder.shared
    private init() {}

    var isModelReady: Bool { diarizer != nil }

    /// Download + load the Sortformer CoreML bundle once (≈12 files; first compile is
    /// slow, then cached). Device-only in practice (ANE).
    func ensureLoaded() async throws {
        guard diarizer == nil else { return }
        // Distinguish a genuine first-time download from a cached reload (each app launch
        // reloads into memory — that's "Preparing", not "Downloading"). Flag set once below.
        let firstTime = !UserDefaults.standard.bool(forKey: "sortformerModelReady")
        await MainActor.run { DiarizationStatus.shared.set(firstTime ? .downloadingModel(nil) : .preparingModel) }
        let models = try await SortformerModels.loadFromHuggingFace(config: config) { progress in
            if firstTime { Task { @MainActor in DiarizationStatus.shared.set(.downloadingModel(progress.fractionCompleted)) } }
        }
        let d = SortformerDiarizer(config: config)
        d.initialize(models: models)
        diarizer = d
        UserDefaults.standard.set(true, forKey: "sortformerModelReady")
    }

    func diarize(audioURL: URL, targetSpeakers: Int?) async throws -> DiarizationOutput {
        try await ensureLoaded()
        await MainActor.run { DiarizationStatus.shared.set(.identifying) }
        guard let diarizer else { throw DiarizationError.notReady }

        diarizer.reset()   // clean per-recording state (slot numbering doesn't carry over)
        let samples = try AudioConverter(sampleRate: 16000).resampleAudioFile(audioURL)
        let timeline = try diarizer.processComplete(samples)

        var segments: [DiarizedSegment] = []
        for (slot, speaker) in timeline.speakers {
            for s in speaker.finalizedSegments {
                segments.append(DiarizedSegment(speaker: slot, start: Double(s.startTime), end: Double(s.endTime)))
            }
        }
        segments.sort { $0.start < $1.start }

        // The pure cluster/identify passes are shared (DiarizingContract); the engine
        // supplies its wespeaker embed — which may surface the voice-model download UI,
        // so each closure call resets the status line back to "Identifying…" after.
        let embed: ([Float]) async throws -> [Float]? = { [embedder] clip in
            let e = try? await embedder.embed(samples: clip)
            await MainActor.run { DiarizationStatus.shared.set(.identifying) }
            return e
        }
        if let target = targetSpeakers {
            segments = await SpeakerIdentification.clusterToTarget(
                segments: segments, samples: samples, target: target, embed: embed)
        }
        let people = NamesStore.shared.livePeople().filter { !($0.voiceEmbeddings?.isEmpty ?? true) }
        let slotNames = await SpeakerIdentification.identify(
            segments: segments, samples: samples, people: people, embed: embed)
        return DiarizationOutput(segments: segments, slotNames: slotNames)
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
/// already-enrolled people (those with a saved voiceprint), simulating the real
/// embedding auto-match.
struct SeededDiarizer: Diarizing {
    var speakers = 2
    var blockSeconds = 4.0
    var totalSeconds = 28.0

    func diarize(audioURL: URL, targetSpeakers: Int?) async throws -> DiarizationOutput {
        let n = max(1, targetSpeakers ?? speakers)   // honour the forced count in the sim
        var segs: [DiarizedSegment] = []
        var t = 0.0, i = 0
        while t < totalSeconds {
            segs.append(DiarizedSegment(speaker: i % n, start: t, end: min(t + blockSeconds, totalSeconds)))
            t += blockSeconds; i += 1
        }
        let enrolled = NamesStore.shared.livePeople()
            .filter { !($0.voiceEmbeddings?.isEmpty ?? true) }
            .map(\.displayName).sorted()
        var slotNames: [Int: String] = [:]
        for slot in 0..<n where slot < enrolled.count { slotNames[slot] = enrolled[slot] }
        return DiarizationOutput(segments: segs, slotNames: slotNames)
    }
}
