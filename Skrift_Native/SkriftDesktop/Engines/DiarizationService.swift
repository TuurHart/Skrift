import Foundation
import FluidAudio

/// Desktop diarization engine: Sortformer splits the recording into speakers ("who spoke
/// when"); then — only when voices are enrolled — wespeaker embeds each speaker's audio
/// and `VoiceMatcher` cosine-matches it against the synced `Person.voiceEmbeddings`
/// ("is this Tiuri?"). The two jobs are separate (Sortformer can't ingest a voiceprint).
/// Lives in `Engines/` (app target only) so FluidAudio stays out of the host-less test
/// target; mirrors the phone's DiarizationService. Models download from HuggingFace on
/// first use and cache (Sortformer ≈ a dozen files; the wespeaker/pyannote bundle is a
/// 2nd, lazy download skipped entirely when nothing is enrolled).
actor DiarizationService: Diarizing {
    static let shared = DiarizationService()

    private let config = SortformerConfig.default
    private var diarizer: SortformerDiarizer?
    private var embedderManager: DiarizerManager?
    private init() {}

    /// Min clip for a trustworthy embedding (≈2s); cap = the wespeaker model's fixed 10s
    /// window (it repeat-pads shorter, longer overflows the buffer).
    private static let minSamples = 32_000
    private static let maxSamples = 160_000

    func ensureDiarizerLoaded() async throws {
        guard diarizer == nil else { return }
        let models = try await SortformerModels.loadFromHuggingFace(config: config)
        let d = SortformerDiarizer(config: config)
        d.initialize(models: models)
        diarizer = d
    }

    func diarize(audioURL: URL) async throws -> DiarizationOutput {
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

        let slotNames = try await identifySpeakers(segments: segments, samples: samples)
        return DiarizationOutput(segments: segments, slotNames: slotNames)
    }

    /// Embed each speaker's audio + cosine-match against known voiceprints. Loads the 2nd
    /// (wespeaker) model lazily and ONLY when there are enrolled voices to match against.
    private func identifySpeakers(segments: [DiarizedSegment], samples: [Float]) async throws -> [Int: String] {
        let people = NamesStore.shared.livePeople().filter { !($0.voiceEmbeddings?.isEmpty ?? true) }
        guard !people.isEmpty else { return [:] }

        var slotNames: [Int: String] = [:]
        for slot in Set(segments.map(\.speaker)).sorted() {
            let clip = Self.clip(segments.filter { $0.speaker == slot }, from: samples)
            guard let embedding = try? await embed(samples: clip) else { continue }
            if let match = VoiceMatcher.bestMatch(embedding: embedding, people: people) {
                slotNames[slot] = match.person.displayName
            }
        }
        return slotNames
    }

    /// Load the wespeaker bundle (lazy, cached) — the 2nd model beyond Sortformer.
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
        guard samples.count >= Self.minSamples else { return nil }
        try await ensureEmbedderLoaded()
        return try embedderManager?.extractSpeakerEmbedding(from: Array(samples.prefix(Self.maxSamples)))
    }

    /// Embed a specific diarized speaker's audio from a memo file — for Mac-originated
    /// enrollment (name a speaker in review → learn their voice → syncs back to the phone).
    func embedSpeaker(audioURL: URL, segments: [DiarizedSegment], slot: Int) async throws -> [Float]? {
        let samples = try AudioConverter(sampleRate: 16000).resampleAudioFile(audioURL)
        return try await embed(samples: Self.clip(segments.filter { $0.speaker == slot }, from: samples))
    }

    /// Concatenate a slot's segments' audio (time-ordered, 16kHz mono) into one clip,
    /// capped at the embedder's max window.
    static func clip(_ segs: [DiarizedSegment], from samples: [Float]) -> [Float] {
        var out: [Float] = []
        for seg in segs.sorted(by: { $0.start < $1.start }) {
            let a = max(0, Int(seg.start * 16000)), b = min(samples.count, Int(seg.end * 16000))
            if a < b { out.append(contentsOf: samples[a..<b]) }
        }
        return Array(out.prefix(maxSamples))
    }
}
