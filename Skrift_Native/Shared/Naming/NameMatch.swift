import Foundation

// Name-match result types — the deterministic name-linker's *suggested/ambiguous* tier.
// SHARED cross-app source (lives in `Skrift_Native/Shared/Naming/`, compiled into BOTH
// apps via each `project.yml`) so the engine's `Result` type is identical on phone and
// Mac. Moved out of the desktop `PipelineFile.swift` in standalone Phase 0 (the phone has
// no `PipelineFile`). Encoding is contract-faithful — mirrors the backend `ambiguous_names`.

/// A candidate person for an ambiguous alias (alias maps to 2+ people).
struct NameCandidate: Codable, Equatable, Sendable {
    var id: String
    var canonical: String
    var short: String
}

/// An ambiguous alias occurrence carried on the note and resolved at review
/// (non-blocking sanitise). Mirrors the backend `ambiguous_names` entries.
struct AmbiguousOccurrence: Codable, Equatable, Sendable {
    var alias: String
    var offset: Int
    var length: Int
    var contextBefore: String
    var contextAfter: String
    var candidates: [NameCandidate]
}

/// One name occurrence rendered over the **RAW** transcript, tiered for the phone's
/// in-place name-linking touch surface (`mocks/phone-name-linking.html`). The phone
/// keeps the transcript RAW and re-derives these on demand via
/// `Sanitiser.nameSpans(inRaw:)` — it NEVER writes `[[brackets]]` into the body, so
/// the offsets index the raw text directly (the displayed spoken word styles by tier
/// and is tappable). Deterministic, LLM-free, derived from the SAME `Overrides` +
/// first-mention logic as `Sanitiser.process`, so the phone's tiers always agree with
/// what the export / the Mac would link.
struct NameSpan: Equatable, Sendable {
    /// LINKED  — this person's FIRST mention (auto-linked or user-picked); shows the
    ///           spoken word in solid accent. One per linked person.
    /// SUGGESTED — a single-candidate FP-prone name (common word / too short) whose
    ///           person did not auto-link; tan dotted, one tap to link.
    /// AMBIGUOUS — an alias 2+ roster people share; purple dotted + "?".
    /// PLAIN   — a name the user explicitly KEPT PLAIN this note (the reversible
    ///           "keep as plain text" / unlink gesture, persisted as a silenced
    ///           `namePicks[alias]=""`); a faint dotted, re-tappable token (the mock's
    ///           `leftplain`) so it can be re-linked inline. Phone-only — `process`
    ///           drops a silenced alias entirely.
    enum Tier: String, Equatable, Sendable { case linked, suggested, ambiguous, plain }

    /// Range into the RAW transcript (the displayed spoken word).
    var offset: Int
    var length: Int
    /// The matched spoken word (what the user said / what's shown).
    var alias: String
    var tier: Tier
    /// The resolved person's canonical (`[[Name]]`) for a linked span, or the single
    /// candidate for a suggested span; nil for an ambiguous span (pick one of `candidates`).
    var canonical: String?
    /// Candidate people for the resolution sheet — one entry for suggested, 2+ for ambiguous.
    var candidates: [NameCandidate]

    var range: NSRange { NSRange(location: offset, length: length) }
}
