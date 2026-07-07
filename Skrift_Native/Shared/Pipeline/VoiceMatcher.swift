import Foundation

/// Identity matching for conversation mode: compares a diarized speaker's voiceprint
/// (a wespeaker embedding) against the saved voiceprints on the known people, and
/// returns the best match above a similarity threshold.
///
/// SHARED (one copy, both apps): the embeddings themselves sync phone↔Mac
/// (`Person.voiceEmbeddings`, union-merged), so both apps MUST score them identically
/// or the same person would be recognised on one device and not the other. Pure +
/// deterministic — no ML, no IO — the embedding EXTRACTION is app-specific (the
/// phone's `SpeakerEmbedder`, the Mac's `DiarizationService` engine) and feeds this.
/// This is the "is this Tiuri?" step, kept separate from diarization ("who spoke
/// when", Sortformer): Sortformer can't ingest an embedding, so identification is a
/// standalone cosine match. The matched name becomes the `**Name:**` turn label.
enum VoiceMatcher {
    /// Cosine-similarity threshold for "same person". Measured in `DiarizeSpike` on real
    /// audio (M4 ANE): genuinely different people score ≤0.22, the same person ≥0.62
    /// (in- and cross-recording) — so 0.5 sits safely in the gap (0.28 above the
    /// different-people ceiling, 0.12 below the same-speaker floor), favouring NO false
    /// matches. Overridable via `UserDefaults("voiceMatchThreshold")` so the threshold
    /// can be tuned without a rebuild.
    static var threshold: Float {
        let t = UserDefaults.standard.double(forKey: "voiceMatchThreshold")
        return t > 0 ? Float(t) : 0.5
    }

    /// True cosine similarity. wespeaker embeddings are NOT unit-norm in practice
    /// (|v|≈2.6–2.9, contrary to the API doc — verified in the spike), so we divide by
    /// magnitudes rather than taking a bare dot product. Returns 0 when the shapes differ
    /// or either side is empty, so a stray-dimension embedding can never spuriously match.
    static func cosine(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        var dot: Float = 0, na: Float = 0, nb: Float = 0
        for i in 0..<a.count { dot += a[i] * b[i]; na += a[i] * a[i]; nb += b[i] * b[i] }
        guard na > 0, nb > 0 else { return 0 }
        return dot / (na.squareRoot() * nb.squareRoot())
    }

    /// Best matching person for `embedding` over everyone's saved voiceprints, or nil if
    /// none clear `threshold`. Matching is MAX-cosine across each person's embedding list
    /// (multi-embedding, never averaged — an AirPods voiceprint and a phone-mic voiceprint
    /// stay distinct so either can match), then the highest-scoring person wins.
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
