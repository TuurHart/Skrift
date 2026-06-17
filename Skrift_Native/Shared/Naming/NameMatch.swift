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
