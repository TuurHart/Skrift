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

// ─────────────────────────────────────────────────────────────────────────────
// Q180 — the RULES behind the menus. Wording/glyph/order were already shared;
// what drifted was WHICH items a surface shows, when Redo is offered, and what
// Copy transcript does when the note is locked or empty. Foundation-only so both
// apps and the desktop unit bundle compile it.
// ─────────────────────────────────────────────────────────────────────────────

/// The menus that list notes' verbs. The two ⋯ menus (open note) are not here: they
/// already render from `NoteMenuItem` in order and gate each item at the call site.
enum NoteMenuSurface: CaseIterable {
    /// Phone / iPad notes-list long-press menu (`MemosListView`).
    case phoneList
    /// Mac sidebar right-click on a rated row (a `PipelineFile`).
    case macList
    /// Mac sidebar right-click on an unrated ("quiet") row (a bare `Memo`).
    case macQuietList
}

extension NoteMenuItem {
    /// Why this item is NOT on `surface`, or nil when it belongs there. An absence is a
    /// declared fact with its reason, never a silent omission (Q180, list-sidebar-83).
    func absence(on surface: NoteMenuSurface) -> String? {
        switch surface {
        case .phoneList:
            switch self {
            case .addRecording, .splitSpeakers, .flattenToMonologue, .retranscribe, .redo,
                 .undoTidyUp, .printCard, .share:
                return "the phone's list menu is quick actions; these act on the OPEN note and live in its ⋯"
            case .copyMarkdown, .revealInFinder, .openInObsidian:
                return "no Finder, no compiled-Markdown copy on the phone (its export is Publish)"
            default: return nil
            }
        case .macList:
            switch self {
            case .addRecording:
                return "acts on the OPEN note: it lives in its ⋯ (NoteActions, Q290)"
            case .splitSpeakers:
                return "not built on the Mac (the split lives on the phone)"
            case .undoTidyUp:
                return "lives in the open note's ⋯ (NoteActions)"
            case .remind:
                return "no Mac set/clear verb or alarm yet (D122 decided, not built)"
            case .printCard:
                return "the wall printer is the phone's (FEATURES.md Desktop ➖)"
            case .lock, .unlock:
                return "a rated row has no cloud write-back for the lock yet (NoteActions.swift); its unrated twin has it"
            case .share:
                return "no share sheet on the Mac (FEATURES.md Desktop ➖)"
            default: return nil
            }
        case .macQuietList:
            switch self {
            case .addRecording, .splitSpeakers, .flattenToMonologue, .retranscribe, .redo,
                 .undoTidyUp, .remind, .printCard, .share:
                return "an unrated note has no pipeline row to act on; open it for the rest"
            case .copyMarkdown:
                return "a bare unrated row cannot compile Markdown; the open note's ⋯ offers it"
            case .revealInFinder, .openInObsidian:
                return "an unrated note has no working folder and has never been exported"
            default: return nil
            }
        }
    }
}

/// What the apps know about one note when a list menu is built. Each app fills it
/// from its own model (`PipelineFile` / `Memo`); `NoteMenuLayout` decides the rest.
struct NoteMenuState: Equatable {
    var locked = false
    var isConversation = false
    var canRetranscribe = false
    var redoOffered = false
    var canUndoTidyUp = false
    var hasWorkingFolder = false
    var hasExportedFile = false
}

enum NoteMenuLayout {
    /// The items a list context menu shows, in `NoteMenuItem` order: not declared absent on
    /// the surface, and whose per-note gate passes. Lock/Remove lock is one slot.
    static func listItems(_ surface: NoteMenuSurface, state: NoteMenuState) -> [NoteMenuItem] {
        NoteMenuItem.allCases.filter { item in
            guard item.absence(on: surface) == nil else { return false }
            switch item {
            case .flattenToMonologue: return state.isConversation
            case .retranscribe:       return state.canRetranscribe
            case .redo:               return state.redoOffered
            case .undoTidyUp:         return state.canUndoTidyUp
            case .lock:               return !state.locked
            case .unlock:             return state.locked
            case .revealInFinder:     return state.hasWorkingFolder
            case .openInObsidian:     return state.hasExportedFile
            default:                  return true
            }
        }
    }
}

extension NoteRedoItem {
    /// The parts a Redo offers. Copy-edit strips a conversation's `**Name:**` turn
    /// prefixes, so conversations keep verbatim (C179): hidden for them, both apps.
    static func offered(isConversation: Bool) -> [NoteRedoItem] {
        isConversation ? [.title, .summary] : [.title, .copyEdit, .summary]
    }

    /// The flat spelling for a menu that cannot nest a submenu (the phone's compact
    /// action dialog): "Redo title", "Redo copy-edit", "Redo summary".
    var flatLabel: String { "\(NoteMenuItem.redo.label) \(label.lowercased())" }

    /// ONE availability rule (C179: offered only where polished + engine + unlocked).
    /// "Polished" = ANY part exists, the phone's `MemoEnhancement.hasContent` — a note whose
    /// model wrote only a summary can still redo its title. (The Mac used to demand all
    /// three, hiding Redo on a note the iPad offered it for.)
    static func isOffered(title: String?, copyEdit: String?, summary: String?,
                          engineAvailable: Bool, locked: Bool) -> Bool {
        guard engineAvailable, !locked else { return false }
        return [title, copyEdit, summary].contains {
            !($0 ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }
}

/// ONE Copy-transcript rule for both apps and every entry point (list menu, note ⋯,
/// compact dialog): a locked note authenticates then copies; an empty one says so.
enum CopyTranscriptRule {
    static let emptyMessage = "Nothing to copy yet"

    enum Step: Equatable {
        /// Locked and not yet unlocked this session: ask for device-owner auth first.
        case authenticate
        case copy(String)
        case nothingToCopy
    }

    /// - Parameters:
    ///   - needsAuth: the note is locked and this session has not unlocked it.
    ///   - text: the text the entry point would copy.
    static func step(needsAuth: Bool, text: String?) -> Step {
        if needsAuth { return .authenticate }
        guard let text, !text.isEmpty else { return .nothingToCopy }
        return .copy(text)
    }
}
