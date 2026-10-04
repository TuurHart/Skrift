import Foundation

/// The triage chips over the notes/queue surface — ONE label set AND one membership rule for
/// every device (the phone and iPad Notes list, the Mac sidebar). Each app hands `admits` the
/// three facts it knows about a row; the rule itself lives here once (C115, D167).
///
/// - `.all`       every note
/// - `.needsWork` rated, not yet processed on any device
/// - `.done`      rated AND processed on any device (D167: Done means processed; 'exported' is
///                the destination row's own state and never enters the filter)
/// - `.notRated`  significance 0 and not locked — waiting on a human, not a model
enum QueueFilter: String, CaseIterable {
    case all = "All", needsWork = "Needs Work", done = "Done", notRated = "Unrated"

    /// THE chip rule. `processed` = a polish pass ran for this note on any device
    /// (`MemoEnhancement.isProcessed`, or the Mac row's own pass before it syncs).
    func admits(rated: Bool, processed: Bool, locked: Bool) -> Bool {
        switch self {
        case .all:       return true
        case .needsWork: return rated && !processed
        case .done:      return rated && processed
        case .notRated:  return !rated && !locked
        }
    }

    /// A memo row. `enhancedIDs` = the memo ids a polish pass has RUN for (any device), built
    /// once per render — never a fetch per memo inside a SwiftUI body.
    func admits(_ memo: Memo, enhancedIDs: Set<UUID>) -> Bool {
        admits(rated: NoteConsent.isRated(memo), processed: enhancedIDs.contains(memo.id),
               locked: memo.locked)
    }
}
