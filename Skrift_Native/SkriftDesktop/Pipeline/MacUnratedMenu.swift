import Foundation

/// The ⋯ menu of an UNRATED note on the Mac (Q127, C40/D159/C187): the iPad's set minus
/// what an unrated note cannot do. It used to be copy-only; the iPad offers Process on the
/// same note and pressing it rates it, so the Mac must have a Process to press.
///
/// Foundation-only and pure so `MacUnratedMenuTests` can pin the set and its order. The
/// wording comes from the shared `NoteMenuItem` / `SharedCopy` tables; the actions stay in
/// `NoteActions` (they need the `Memo`, the lock gate and the cloud store).
enum MacUnratedMenu {
    enum Entry: Equatable {
        /// Press = judgment: floors the rating (`NoteConsent.flooredByProcess`), after which the
        /// note enters the ordinary queue. Not a `NoteMenuItem` case (the iPad's Process is its
        /// primary button), so it names itself from `SharedCopy.processVerb`.
        case process
        case item(NoteMenuItem)
    }

    /// Order follows `NoteMenuItem` (to the note, with the note, delete last), with Process
    /// first because it is the one verb that changes what the note IS.
    /// - Parameters:
    ///   - rated: a RATED projection (just rated, its real row not swept in yet) has already
    ///     been judged, so Process is not offered again.
    static func entries(rated: Bool, locked: Bool, canUndoTidyUp: Bool) -> [Entry] {
        var out: [Entry] = []
        if !rated { out.append(.process) }
        if canUndoTidyUp { out.append(.item(.undoTidyUp)) }
        out.append(.item(NoteMenuItem.lockItem(isLocked: locked)))
        out.append(.item(.copyTranscript))
        out.append(.item(.copyMarkdown))
        out.append(.item(.delete))
        return out
    }

    static func label(_ entry: Entry) -> String {
        switch entry {
        case .process: return SharedCopy.processVerb
        case .item(let i): return i.label
        }
    }
}
