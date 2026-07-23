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

    /// THE verb for running a note through the model — the Mac's word since day
    /// one, adopted verbatim by the iPad (Tuur, 2026-07-23: "I don't know why
    /// it's called polish, if it's called Process on the Mac… we should have
    /// shared names for everything"). The iPad shipped "Polish" for a day; this
    /// constant is why it can't happen again. Internal names (`PolishCenter`,
    /// `MLXPolishEngine`, `PolishPrompts`) deliberately stay — the rename rule
    /// is display-only.
    static let processVerb = "Process"

    /// Settings destination for the on-device model + prompts (iPad).
    static let processSettingsTitle = "Process on this iPad"

    /// The in-flight line while a note is being processed on THIS device.
    /// `step` is the model pass ("Copy-edit"), `n`/`of` the Mac's RunState
    /// counting — one vocabulary on every screen.
    static func processingStep(_ step: String, _ n: Int, of total: Int) -> String {
        "\(step) · \(n) of \(total)"
    }

    /// First-run model fetch, same fraction the Mac's RunState publishes.
    static func processingDownload(_ fraction: Double) -> String {
        "Getting the model — \(Int((fraction * 100).rounded()))%"
    }
}
