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
    /// The name-linked form of `rawTranscript` — the shared export linker
    /// (`CompilerInput.linkBody`, Q155), so the phone and the Mac route and link one way.
    /// Returns the input unchanged when there's nothing to link (empty text, or no live people).
    static func linkedTranscript(_ rawTranscript: String?, source: NoteSourceType = .audio, people: [Person],
                                 resolutions: NameResolutions = NameResolutions()) -> String {
        CompilerInput.linkBody(rawTranscript ?? "", source: source, people: people, resolutions: resolutions)
    }
}
