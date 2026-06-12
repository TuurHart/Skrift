import Foundation

/// Enrolls a speaker's voiceprint under a name: embed a clip of their audio and add the
/// embedding to the person. Uses `NamesStore.addVoiceEmbedding`, which APPENDS to an
/// existing person (union, de-duped) without touching their Mac-synced aliases/short — so
/// naming a speaker after the Mac has set up that person never clobbers anything — and
/// creates the person if new. The embedding then syncs to the Mac and the person shows
/// "Voice enrolled" in Names & voices.
///
/// Factored out of the naming UI so the embed→store wiring is unit-testable with a seeded
/// embedder + a synthetic clip (the audio extraction + real wespeaker stay device-only).
enum VoiceEnroller {
    /// Returns true if a voiceprint was stored. A too-short or unembeddable clip is a
    /// no-op (false) — the caller has already applied the name to the transcript, so the
    /// label sticks even when there isn't enough audio to learn the voice.
    @discardableResult
    static func enroll(
        name: String, clip: [Float],
        using embedder: any SpeakerEmbedding,
        into store: NamesStore = .shared,
        condition: String = "conversation"
    ) async -> Bool {
        guard clip.count >= SpeakerEmbedder.minSamples,
              let embedding = try? await embedder.embed(samples: clip), !embedding.isEmpty else { return false }
        store.addVoiceEmbedding(
            canonical: name,
            embedding: VoiceEmbedding(vector: embedding.map(Double.init), condition: condition, addedAt: ISO8601.now())
        )
        // Auto-push the new voiceprint to the Mac (debounced, no-op unpaired) —
        // without this it only synced on a manual sync tap, so cross-device
        // auto-match silently lacked the voice. Real store only: test enrolls
        // pass their own.
        if store === NamesStore.shared {
            await MainActor.run { NamesAutoSync.kick() }
        }
        return true
    }
}
