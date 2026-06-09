import Foundation
import FluidAudio

/// Diarization result: speaker time-ranges + the matched name per slot (a slot is named
/// when its voiceprint cosine-matches a known person; nil otherwise → "Speaker N").
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

        let slotNames = await identifySpeakers(segments: segments, samples: samples)
        return DiarizationOutput(segments: segments, slotNames: slotNames)
    }

    /// Embed each speaker's audio and cosine-match it against known voiceprints. Returns
    /// slot → matched display name. Loads the 2nd (wespeaker) model lazily — and ONLY when
    /// there are enrolled voices to match against, so a first-ever conversation (no voices
    /// yet) doesn't pay for it.
    private func identifySpeakers(segments: [DiarizedSegment], samples: [Float]) async -> [Int: String] {
        let people = NamesStore.shared.livePeople().filter { !($0.voiceEmbeddings?.isEmpty ?? true) }
        guard !people.isEmpty else { return [:] }

        var slotNames: [Int: String] = [:]
        for slot in Set(segments.map(\.speaker)).sorted() {
            let clip = Self.clip(segments.filter { $0.speaker == slot }, from: samples)
            guard clip.count >= SpeakerEmbedder.minSamples,
                  let embedding = try? await embedder.embed(samples: clip) else { continue }
            // embed() may have shown the voice-model download; back to "Identifying…".
            await MainActor.run { DiarizationStatus.shared.set(.identifying) }
            if let match = VoiceMatcher.bestMatch(embedding: embedding, people: people) {
                slotNames[slot] = match.person.displayName
            }
        }
        return slotNames
    }

    /// Concatenate a slot's segments' audio (time-ordered, 16kHz mono) into one clip,
    /// capped at the embedder's max window. Shared with the naming/enroll path. `static`
    /// → callable off the actor (the View's enroll task resamples then slices).
    static func clip(_ segs: [DiarizedSegment], from samples: [Float]) -> [Float] {
        var out: [Float] = []
        for seg in segs.sorted(by: { $0.start < $1.start }) {
            let a = max(0, Int(seg.start * 16000)), b = min(samples.count, Int(seg.end * 16000))
            if a < b { out.append(contentsOf: samples[a..<b]) }
        }
        return Array(out.prefix(SpeakerEmbedder.maxSamples))
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

    func diarize(audioURL: URL) async throws -> DiarizationOutput {
        var segs: [DiarizedSegment] = []
        var t = 0.0, i = 0
        while t < totalSeconds {
            segs.append(DiarizedSegment(speaker: i % speakers, start: t, end: min(t + blockSeconds, totalSeconds)))
            t += blockSeconds; i += 1
        }
        let enrolled = NamesStore.shared.livePeople()
            .filter { !($0.voiceEmbeddings?.isEmpty ?? true) }
            .map(\.displayName).sorted()
        var slotNames: [Int: String] = [:]
        for slot in 0..<speakers where slot < enrolled.count { slotNames[slot] = enrolled[slot] }
        return DiarizationOutput(segments: segs, slotNames: slotNames)
    }
}
