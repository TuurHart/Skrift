import Foundation

/// Collapses an over-segmented diarization down to a target speaker count by merging the
/// most voice-similar slots. Sortformer's slot count isn't a knob (the model always emits
/// up to 4), so "split into N speakers" is enforced here: embed each slot, then
/// agglomeratively merge the closest pair until N remain. Pure (cosine over given
/// embeddings) so it's unit-tested; the embedding extraction lives in `DiarizationService`.
enum SpeakerClustering {
    /// A mapping `oldSlot → survivingSlot` that merges `embeddings`'s slots down to
    /// `target` by repeatedly merging the two highest-cosine slots. Slots not in
    /// `embeddings` (too short to embed) are left for the caller to fold by time.
    static func merge(embeddings: [Int: [Float]], target: Int) -> [Int: Int] {
        var mapping = Dictionary(uniqueKeysWithValues: embeddings.keys.map { ($0, $0) })
        var active = Array(embeddings.keys).sorted()
        guard target >= 1, active.count > target else { return mapping }

        while active.count > target {
            var best: (a: Int, b: Int, sim: Float)?
            for i in 0..<active.count {
                for j in (i + 1)..<active.count {
                    let sim = VoiceMatcher.cosine(embeddings[active[i]]!, embeddings[active[j]]!)
                    if best == nil || sim > best!.sim { best = (active[i], active[j], sim) }
                }
            }
            guard let m = best else { break }
            // Merge the higher slot id into the lower (stable), repointing anything mapped to it.
            let (keep, drop) = (min(m.a, m.b), max(m.a, m.b))
            for (k, v) in mapping where v == drop { mapping[k] = keep }
            active.removeAll { $0 == drop }
        }
        return mapping
    }
}
