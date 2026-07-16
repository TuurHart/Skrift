import Foundation

// The diarization seam + its pure logic, ONE copy for both apps (SharedKit
// wave 2; previously twinned mobile DiarizationService.swift vs desktop
// Diarizing.swift, with the clip/identify/cluster logic hand-mirrored). The
// FluidAudio engines (Sortformer + wespeaker) stay per-app in the engine
// layer and pass an `embed` closure into the pure functions here.

/// Diarization result: speaker time-ranges + the matched name per slot (a slot is
/// named when its voiceprint cosine-matches a known person; nil otherwise →
/// "Speaker N").
struct DiarizationOutput: Sendable {
    let segments: [DiarizedSegment]
    let slotNames: [Int: String]
}

/// Splits a recording into speakers ("who spoke when") + matches each to a known
/// voice ("is this Tiuri?"). Real impl = Sortformer + wespeaker via FluidAudio
/// (each app's engine layer, ANE); tests/sim inject stubs or seeded diarizers.
protocol Diarizing: Sendable {
    /// `targetSpeakers` forces the result down to exactly N voices by merging the
    /// most voice-similar slots (the over-segmentation fix); nil = Auto (trust
    /// Sortformer).
    func diarize(audioURL: URL, targetSpeakers: Int?) async throws -> DiarizationOutput
}

extension Diarizing {
    /// Auto speaker count (the Mac's batch path).
    func diarize(audioURL: URL) async throws -> DiarizationOutput {
        try await diarize(audioURL: audioURL, targetSpeakers: nil)
    }
}

/// Slot-clip math over 16kHz mono samples — shared by diarization, identification,
/// and enrollment on both apps.
enum SpeakerAudio {
    /// Min clip for a trustworthy embedding (≈2s); cap = the wespeaker model's
    /// fixed 10s window (it repeat-pads shorter, longer overflows the buffer).
    static let minSamples = 32_000
    static let maxSamples = 160_000

    /// Concatenate a slot's segments' audio (time-ordered, 16kHz mono) into one
    /// clip, capped at the embedder's max window.
    static func clip(_ segs: [DiarizedSegment], from samples: [Float]) -> [Float] {
        var out: [Float] = []
        for seg in segs.sorted(by: { $0.start < $1.start }) {
            let a = max(0, Int(seg.start * 16000)), b = min(samples.count, Int(seg.end * 16000))
            if a < b { out.append(contentsOf: samples[a..<b]) }
        }
        return Array(out.prefix(maxSamples))
    }
}

/// The pure identify/refine passes over a diarization — the engine supplies only
/// the `embed` closure (wespeaker voiceprint for a clip, nil when too short).
enum SpeakerIdentification {

    /// Embed each speaker's audio and cosine-match it against known voiceprints.
    /// Returns slot → matched display name. `people` should be pre-filtered to
    /// those with enrolled voices; when empty the whole pass (and the lazy 2nd
    /// model load inside `embed`) is skipped.
    static func identify(segments: [DiarizedSegment], samples: [Float], people: [Person],
                         embed: ([Float]) async throws -> [Float]?) async -> [Int: String] {
        guard !people.isEmpty else { return [:] }
        var slotNames: [Int: String] = [:]
        for slot in Set(segments.map(\.speaker)).sorted() {
            let clip = SpeakerAudio.clip(segments.filter { $0.speaker == slot }, from: samples)
            guard clip.count >= SpeakerAudio.minSamples,
                  let embedding = try? await embed(clip) else { continue }
            if let match = VoiceMatcher.bestMatch(embedding: embedding, people: people) {
                slotNames[slot] = match.person.displayName
            }
        }
        return slotNames
    }

    /// Force the result down to `target` voices: embed each slot, agglomeratively
    /// merge the closest pair (`SpeakerClustering`), and fold any too-short-to-embed
    /// slot into the embeddable slot nearest in time. Can only merge DOWN — a true
    /// single-speaker recording stays one.
    static func clusterToTarget(segments: [DiarizedSegment], samples: [Float], target: Int,
                                embed: ([Float]) async throws -> [Float]?) async -> [DiarizedSegment] {
        let slots = Set(segments.map(\.speaker)).sorted()
        guard target >= 1, slots.count > target else { return segments }

        var emb: [Int: [Float]] = [:]
        for s in slots {
            let clip = SpeakerAudio.clip(segments.filter { $0.speaker == s }, from: samples)
            if let e = try? await embed(clip) { emb[s] = e }
        }
        guard !emb.isEmpty else { return segments }

        var mapping = SpeakerClustering.merge(embeddings: emb, target: target)
        for tiny in slots where emb[tiny] == nil {   // too short to embed → fold by time
            if let nearest = nearestEmbeddableSlot(to: tiny, embeddable: Array(emb.keys), segments: segments) {
                mapping[tiny] = mapping[nearest] ?? nearest
            }
        }
        return segments.map { DiarizedSegment(speaker: mapping[$0.speaker] ?? $0.speaker, start: $0.start, end: $0.end) }
    }

    /// The embeddable slot whose segments fall closest in time to `slot`'s segments.
    static func nearestEmbeddableSlot(to slot: Int, embeddable: [Int], segments: [DiarizedSegment]) -> Int? {
        let mine = segments.filter { $0.speaker == slot }
        guard !mine.isEmpty, !embeddable.isEmpty else { return nil }
        func gap(_ a: DiarizedSegment, _ b: DiarizedSegment) -> Double {
            if a.end < b.start { return b.start - a.end }
            if b.end < a.start { return a.start - b.end }
            return 0   // overlap
        }
        var best: (slot: Int, gap: Double)?
        for e in embeddable {
            for es in segments where es.speaker == e {
                for ms in mine where best == nil || gap(ms, es) < best!.gap {
                    best = (e, gap(ms, es))
                }
            }
        }
        return best?.slot
    }
}
