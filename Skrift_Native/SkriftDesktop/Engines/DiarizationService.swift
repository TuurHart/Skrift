import Foundation
import FluidAudio

/// Desktop diarization engine: Sortformer splits the recording into speakers ("who spoke
/// when"); then — only when voices are enrolled — wespeaker embeds each speaker's audio
/// and `VoiceMatcher` cosine-matches it against the synced `Person.voiceEmbeddings`
/// ("is this Tiuri?"). The two jobs are separate (Sortformer can't ingest a voiceprint).
/// Lives in `Engines/` (app target only) so FluidAudio stays out of the host-less test
/// target; the contract + pure passes are SHARED (Shared/Pipeline/DiarizingContract.swift),
/// this engine binds them to FluidAudio. Models download from HuggingFace on first use
/// and cache (Sortformer ≈ a dozen files; the wespeaker/pyannote bundle is a 2nd, lazy
/// download skipped entirely when nothing is enrolled).
actor DiarizationService: Diarizing {
    static let shared = DiarizationService()

    private let config = SortformerConfig.default
    private var diarizer: SortformerDiarizer?
    private var embedderManager: DiarizerManager?
    private init() {}

    func ensureDiarizerLoaded() async throws {
        guard diarizer == nil else { return }
        let models = try await SortformerModels.loadFromHuggingFace(config: config)
        let d = SortformerDiarizer(config: config)
        d.initialize(models: models)
        diarizer = d
    }

    func diarize(audioURL: URL, targetSpeakers: Int?) async throws -> DiarizationOutput {
        try await ensureDiarizerLoaded()
        guard let diarizer else { return DiarizationOutput(segments: [], slotNames: [:]) }

        diarizer.reset()
        let samples = try AudioConverter(sampleRate: 16000).resampleAudioFile(audioURL)
        let timeline = try diarizer.processComplete(samples)

        var segments: [DiarizedSegment] = []
        for (slot, speaker) in timeline.speakers {
            for s in speaker.finalizedSegments {
                segments.append(DiarizedSegment(speaker: slot, start: Double(s.startTime), end: Double(s.endTime)))
            }
        }
        segments.sort { $0.start < $1.start }

        // The pure cluster/identify passes are shared (DiarizingContract); this engine
        // supplies only the wespeaker embed. targetSpeakers came with the unification —
        // the phone's force-to-N merge now works on the Mac too.
        let embed: ([Float]) async throws -> [Float]? = { try await self.embed(samples: $0) }
        if let target = targetSpeakers {
            segments = await SpeakerIdentification.clusterToTarget(
                segments: segments, samples: samples, target: target, embed: embed)
        }
        let people = NamesStore.shared.livePeople().filter { !($0.voiceEmbeddings?.isEmpty ?? true) }
        let slotNames = await SpeakerIdentification.identify(
            segments: segments, samples: samples, people: people, embed: embed)
        return DiarizationOutput(segments: segments, slotNames: slotNames)
    }

    /// Load the wespeaker bundle (lazy, cached) — the 2nd model beyond Sortformer.
    /// Loaded ONLY when a pass actually embeds (enrolled voices exist / force-to-N).
    func ensureEmbedderLoaded() async throws {
        guard embedderManager == nil else { return }
        let models = try await DiarizerModels.downloadIfNeeded()
        let m = DiarizerManager()
        m.initialize(models: models)
        embedderManager = m
    }

    /// A 256-dim wespeaker voiceprint for one speaker's clip (≥2s; capped at 10s). nil if
    /// too short. The shared embed path for matching AND Mac-originated enrollment.
    func embed(samples: [Float]) async throws -> [Float]? {
        guard samples.count >= SpeakerAudio.minSamples else { return nil }
        try await ensureEmbedderLoaded()
        return try embedderManager?.extractSpeakerEmbedding(from: Array(samples.prefix(SpeakerAudio.maxSamples)))
    }

    /// Embed a specific diarized speaker's audio from a memo file — for Mac-originated
    /// enrollment (name a speaker in review → learn their voice → syncs back to the phone).
    func embedSpeaker(audioURL: URL, segments: [DiarizedSegment], slot: Int) async throws -> [Float]? {
        let samples = try AudioConverter(sampleRate: 16000).resampleAudioFile(audioURL)
        return try await embed(samples: SpeakerAudio.clip(segments.filter { $0.speaker == slot }, from: samples))
    }
}
