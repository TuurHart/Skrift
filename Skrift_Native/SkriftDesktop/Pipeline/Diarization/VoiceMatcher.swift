import Foundation

/// Identity matching for conversation mode: compares a diarized speaker's voiceprint
/// (a wespeaker embedding) against the saved voiceprints on the known people and returns
/// the best match above a similarity threshold. Pure + deterministic (no ML / IO), ported
/// verbatim from the phone so both apps recognise the same voices from the same synced
/// `Person.voiceEmbeddings`.
enum VoiceMatcher {
    /// Cosine-similarity threshold for "same person". Measured in `DiarizeSpike` on real
    /// audio: different people score ≤0.22, the same person ≥0.62 → 0.5 sits safely in the
    /// gap, favouring NO false matches. Overridable via `UserDefaults("voiceMatchThreshold")`.
    static var threshold: Float {
        let t = UserDefaults.standard.double(forKey: "voiceMatchThreshold")
        return t > 0 ? Float(t) : 0.5
    }

    /// True cosine similarity. wespeaker embeddings are NOT unit-norm in practice, so we
    /// divide by magnitudes. Returns 0 when shapes differ or either side is empty.
    static func cosine(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        var dot: Float = 0, na: Float = 0, nb: Float = 0
        for i in 0..<a.count { dot += a[i] * b[i]; na += a[i] * a[i]; nb += b[i] * b[i] }
        guard na > 0, nb > 0 else { return 0 }
        return dot / (na.squareRoot() * nb.squareRoot())
    }

    /// Best matching person for `embedding` over everyone's saved voiceprints, or nil if
    /// none clear `threshold`. MAX-cosine across each person's list (multi-embedding,
    /// never averaged), then the highest-scoring person wins.
    static func bestMatch(
        embedding: [Float], people: [Person], threshold: Float = VoiceMatcher.threshold
    ) -> (person: Person, similarity: Float)? {
        guard !embedding.isEmpty else { return nil }
        var best: (person: Person, similarity: Float)?
        for p in people {
            guard let embs = p.voiceEmbeddings, !embs.isEmpty else { continue }
            let s = embs.map { cosine(embedding, $0.vector.map(Float.init)) }.max() ?? 0
            if s > (best?.similarity ?? -.infinity) { best = (p, s) }
        }
        guard let best, best.similarity >= threshold else { return nil }
        return best
    }
}
