import Foundation

/// The triage chips over the notes/queue surface — ONE label set for both apps
/// (the Mac sidebar and the iPad Notes column), so a chip means the same word on
/// each. Each app matches it against its OWN model (the Mac against a
/// `PipelineFile`, the iPad against a `Memo` via `ProcessPile`), but the cases
/// and their user-facing words live here once.
///
/// The mapping the iPad uses (a memo has no export step, so "done" = processed):
/// - `.all`       every note
/// - `.needsWork` rated, not yet processed on any device (the to-process pile)
/// - `.done`      rated AND processed (a `MemoEnhancement` with content exists)
/// - `.notRated`  significance 0 — waiting on a human, not a model
enum QueueFilter: String, CaseIterable {
    case all = "All", needsWork = "Needs Work", done = "Done", notRated = "Unrated"
}
