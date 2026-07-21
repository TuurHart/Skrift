import Foundation

/// Cross-app user-facing labels — single-sourced so the two apps can't drift
/// (the "Journal" vs "Review" fork happened twice; memory
/// `feedback_shared_code_first`). Internal identifiers (types, keys, file
/// names) deliberately do NOT follow display renames.
enum SharedCopy {
    /// The review/journal surface: the phone tab + screen title, the Mac's
    /// sidebar mode pill + column header. Display name "Review" (Tuur,
    /// 2026-07-07; Mac holdouts fixed 2026-07-16).
    static let reviewTitle = "Review"

    /// The notes-list surface: the phone's first tab + the Mac's sidebar mode
    /// pill (was "Queue" on the Mac — Tuur 2026-07-21: match the phone; the
    /// pipeline machinery keeps its internal names).
    static let notesTitle = "Notes"
}
