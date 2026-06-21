import Foundation

/// Derives the name-LINKED form of a memo's transcript on demand. The phone runs the SAME
/// shared `Sanitiser` over its local names DB that the Mac runs, so the standalone Obsidian
/// export (Phase 2) gets `[[Name]]` links — WITHOUT storing a derived field.
///
/// Re-derivation (not a stored `sanitised` column) is deliberate:
/// - `Memo.transcript` stays RAW — the contract spine the Mac trusts (the phone still uploads
///   RAW; the Mac re-links identically via the SAME shared engine + synced names DB → no
///   double-link, no skip-signal; STANDALONE_PLAN "Cross-app consistency").
/// - A names edit (add a person, fix an alias) is reflected the next time you export — never a
///   stale link baked into the row.
///
/// Pure (people injected) → fully testable; the engine itself lives in `Shared/Naming`.
enum MemoLinking {
    /// The name-linked form of `rawTranscript`. Routes attributed (≥2 speaker-turn)
    /// transcripts through the conversation linker and everything else through the monologue
    /// linker — mirroring the Mac's `BatchRunner` routing (it picks `processConversation` for
    /// `SpeakerTranscript`-attributed text). Returns the input unchanged when there's nothing
    /// to link (empty text, or no live people).
    static func linkedTranscript(_ rawTranscript: String?, people: [Person]) -> String {
        guard let raw = rawTranscript, !raw.isEmpty else { return rawTranscript ?? "" }
        let live = people.filter { !$0.isDeleted }
        guard !live.isEmpty else { return raw }
        if SpeakerTranscript.parse(raw) != nil {
            return Sanitiser.processConversation(text: raw, people: live).sanitised
        }
        return Sanitiser.process(text: raw, people: live).sanitised
    }

    /// Convenience over the live on-device names DB (`NamesStore`). Use the people-injected
    /// overload in tests / where the roster is already loaded.
    static func linkedTranscript(_ rawTranscript: String?) -> String {
        linkedTranscript(rawTranscript, people: NamesStore.shared.load().people)
    }
}
