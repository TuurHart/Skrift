import Foundation

/// THE note overflow (⋯) menu's vocabulary — one list, two renderers (Tuur,
/// 2026-07-25, after noticing the Mac's ⋯ held two items while the iPad's held
/// eight: "I don't know why…").
///
/// What is shared here is the **wording, the SF Symbol and the ORDER** — the
/// things that silently drift (the Journal-vs-Review lesson, `SharedCopy`). What
/// is deliberately NOT shared is the actions themselves: the Mac acts on a
/// `PipelineFile` through `ProcessingCoordinator`, the phone on a `Memo` through
/// `NotesRepository`, so each app builds its own buttons — but it must take the
/// label, glyph and position from here, and render the items it can actually
/// perform in this order. An app omitting an item is normal (no sharing on the
/// Mac, no Finder on the phone); an app *renaming* or *reordering* one is drift.
///
/// Order = declaration order (`allCases`): what you do TO the recording, then
/// what you do WITH the note, then the destructive verb last.
enum NoteMenuItem: CaseIterable {
    // ── to the recording ──
    case addRecording
    case splitSpeakers
    case flattenToMonologue
    case retranscribe
    case redo
    case undoTidyUp
    // ── with the note ──
    // No `viewThread`: retired from BOTH apps 2026-07-25 — Connections' Date mode
    // is the arc on every platform (Tuur: "keep the apps looking the same").
    case remind
    case printCard
    case lock
    case unlock
    case share
    case copyTranscript
    case copyMarkdown
    case revealInFinder
    case openInObsidian
    // ── last ──
    case delete

    var label: String {
        switch self {
        case .addRecording:       return "Add recording"
        case .splitSpeakers:      return "Split speakers"
        case .flattenToMonologue: return "Flatten to monologue"
        case .retranscribe:       return "Re-transcribe"
        case .redo:               return "Redo"
        case .undoTidyUp:         return "Undo tidy-up"
        case .remind:             return "Remind me…"
        case .printCard:          return "Print card"
        case .lock:               return "Lock note"
        case .unlock:             return "Remove lock"
        case .share:              return "Share note…"
        case .copyTranscript:     return "Copy transcript"
        case .copyMarkdown:       return "Copy as Markdown"
        case .revealInFinder:     return "Reveal in Finder"
        case .openInObsidian:     return "Open in Obsidian"
        case .delete:             return "Delete"
        }
    }

    /// SF Symbol. The phone/iPad draws these in `Label`s; macOS menus are
    /// text-only, so the Mac ignores them — they still live here so the two apps
    /// can never pick different glyphs for the same verb.
    var systemImage: String {
        switch self {
        case .addRecording:       return "plus"
        case .splitSpeakers:      return "person.2.fill"
        case .flattenToMonologue: return "text.alignleft"
        case .retranscribe:       return "waveform"
        case .redo:               return "arrow.clockwise"
        case .undoTidyUp:         return "arrow.uturn.backward"
        case .remind:             return "bell"
        case .printCard:          return "printer"
        case .lock:               return "lock"
        case .unlock:             return "lock.open"
        case .share:              return "square.and.arrow.up"
        case .copyTranscript:     return "doc.on.doc"
        case .copyMarkdown:       return "doc.richtext"
        case .revealInFinder:     return "folder"
        case .openInObsidian:     return "arrow.up.forward.app"
        case .delete:             return "trash"
        }
    }

    /// The lock verb reads off current state rather than being two call sites.
    static func lockItem(isLocked: Bool) -> NoteMenuItem { isLocked ? .unlock : .lock }
}

/// The `Redo` submenu's parts — same rule: one wording, both apps.
enum NoteRedoItem: CaseIterable {
    case title, copyEdit, summary

    var label: String {
        switch self {
        case .title:    return "Title"
        case .copyEdit: return "Copy-edit"
        case .summary:  return "Summary"
        }
    }
}
