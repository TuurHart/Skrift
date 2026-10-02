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

    /// THE verb for bringing external audio/video in — "Import" on both apps
    /// (Tuur, 2026-07-23: "make both mac and ipad import"; the Mac's button said
    /// "Upload"). The Mac still opens its file panel, the iPad offers Files vs
    /// Photos — same word, each platform's own picker.
    static let importVerb = "Import"

    /// The notes-search field placeholder — "Search memos" everywhere (Tuur,
    /// 2026-07-23: the phone/iPad said "Search transcripts"; the Mac's wording
    /// wins — "search memos should be done everywhere").
    static let searchPlaceholder = "Search memos"

    /// The in-flight line while a note is being processed on THIS device.
    /// `step` is the model pass ("Copy-edit"), `n`/`of` the Mac's RunState
    /// counting — one vocabulary on every screen.
    static func processingStep(_ step: String, _ n: Int, of total: Int) -> String {
        "\(step) · \(n) of \(total)"
    }

    /// The BULK line while a pile runs — the Mac's run-bar wording, now shared
    /// so the iPad's header says exactly what the Mac's has always said.
    static func processingCount(_ n: Int, of total: Int) -> String {
        "Processing \(n) of \(total)"
    }

    /// First-run model fetch, same fraction the Mac's RunState publishes.
    static func processingDownload(_ fraction: Double) -> String {
        "Getting the model — \(Int((fraction * 100).rounded()))%"
    }

    // ── Q108: strings that were typed twice (parity audit P9) ──

    /// THE verb for starting a take — the red-dot button in the notes verb row
    /// on the phone, iPad and Mac.
    static let recordVerb = "Record"

    /// "Back" — leaving the Places map / Fading column on the Mac, the Places
    /// map on the iPad (was 'back to calendar' there).
    static let backVerb = "Back"

    /// Empty library. The body names the two buttons that exist (D136: the mic
    /// corner button is gone; the Mac button is "Import", not "Upload").
    static let emptyLibraryTitle = "No notes yet"
    static let emptyLibraryBody = "Tap \(recordVerb) to capture your first note, or \(importVerb) audio you already have."

    /// Search/filter excluded every note.
    static let noMatchesTitle = "No matches"
    static func noMatchesBody(_ query: String) -> String { "Nothing matches “\(query)”." }

    /// Review's one-sentence intro / empty state, in the phone's two lines (the Mac joins them).
    static let reviewIntroLines = ["As your notes age, past thinking resurfaces here —",
                                   "a month ago, a year ago, on this day."]
    static var reviewIntro: String { reviewIntroLines.joined(separator: " ") }

    /// Review's selected day with nothing in it.
    static let reviewEmptyDay = "Nothing recorded this day."

    /// The Fading shelf (phone sheet, Mac column). The numbers come from
    /// `MemoLifecycle.fadeAfterDays` / `TrashPolicy.retentionDays`, never a literal.
    static let wayOutEmptyTitle = "Nothing is fading"
    static var wayOutEmptyBody: String {
        "Quiet notes start fading \(MemoLifecycle.fadeAfterDays) days after you last touch them."
    }
    static let wayOutIntro = "Everything leaving, soonest first. Quiet notes leave on their own when their clock runs out; Bring back rescues one from any point."
    static let wayOutFadingLabel = "Still visible → moving to Recently Deleted"
    static let wayOutDeletedLabel = "In Recently Deleted → gone for good"
    static var wayOutFooter: String {
        "Automatic: each note moves along on its day. Deleted notes are kept for \(TrashPolicy.retentionDays) days, then removed for good. Bring back gives a note a fresh \(MemoLifecycle.fadeAfterDays) days."
    }

    /// The peek before a rescue.
    static let peekNoTranscript = "No transcript yet."
    static var peekUndoLine: String { "to Recently Deleted · \(TrashPolicy.retentionDays) days to undo" }

    /// The run bar while a model loads: "Loading transcription model · 1 of 2".
    static func processingLoading(_ what: String) -> String { "Loading \(what)" }
}
