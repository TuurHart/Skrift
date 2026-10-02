import Foundation

/// ONE note-search matcher for the phone list, the iPad list, the Mac rated list and the
/// Mac quiet (unrated) list (Q103, C236/C111/C115). Before this the three sites each
/// hand-listed their own fields and drifted: the phone missed the generated title and the
/// summary, the Mac rated list missed tags/place/annotation/link text, the Mac quiet list
/// matched title + transcript only.
///
/// Every field a surface holds goes into a `NoteSearchSnapshot` (a plain value — no
/// `@Model`, no view state); this file decides which fields count and routes the lock rule
/// through `NoteVisibility.matches`, so a locked note's body stays out of the match.
///
/// This is LIST search. OCR text is a list-search-only field (C236): it rides in the
/// snapshot and nowhere else (not the semantic index, not link pickers).
struct NoteSearchSnapshot: Sendable, Equatable {
    var locked: Bool = false
    var unlockedThisSession: Bool = false
    /// The title the row still shows while the note is locked (the user's set title; on the
    /// Mac the polish title). The only field that can hit a hidden locked note.
    var title: String?
    // Everything below is the note's content: out of the match while hidden.
    /// The Mac polish's generated title, when it is not already `title`.
    var generatedTitle: String?
    /// The title a row derives when nothing is set (the Mac's file-name fallback).
    var derivedTitle: String?
    var transcript: String?
    var summary: String?
    var tags: [String] = []
    var place: String?
    var annotation: String?
    /// A shared link's title/description, shared text, or a shared file's name (PDF).
    var shared: [String?] = []
    /// Photo OCR text, one entry per photo — list search only.
    var ocr: [String?] = []
}

enum NoteSearch {
    /// Empty (or whitespace) query matches everything. Case-insensitive substring over
    /// the snapshot's fields; a hidden locked note matches on `title` alone.
    static func matches(query: String, _ s: NoteSearchSnapshot) -> Bool {
        NoteVisibility.matches(query: query, locked: s.locked,
                               unlockedThisSession: s.unlockedThisSession,
                               title: s.title, bodyFields: {
            var f: [String?] = [s.generatedTitle, s.derivedTitle, s.transcript, s.summary,
                                s.place, s.annotation]
            f.append(contentsOf: s.tags.map { Optional($0) })
            f.append(contentsOf: s.shared)
            f.append(contentsOf: s.ocr)
            return f
        })
    }
}

extension Memo {
    /// The search snapshot of a synced `Memo` — used by the phone/iPad list and the Mac's
    /// quiet rows. `enhancedTitle` / `summary` come from the memo's `MemoEnhancement` when
    /// the caller has it (a Memo does not carry them).
    func noteSearchSnapshot(unlockedThisSession: Bool, enhancedTitle: String? = nil,
                            summary: String? = nil) -> NoteSearchSnapshot {
        let sc = sharedContent
        return NoteSearchSnapshot(
            locked: locked, unlockedThisSession: unlockedThisSession,
            title: title, generatedTitle: enhancedTitle, derivedTitle: nil,
            transcript: transcript, summary: summary, tags: tags,
            place: metadata?.location?.placeName, annotation: annotationText,
            shared: [sc?.urlTitle, sc?.urlDescription, sc?.text, sc?.fileName],
            ocr: (metadata?.imageManifest ?? []).map { $0.text })
    }
}
